#!/usr/bin/env bash
# Shared helpers for the Docker lineage lab against tomjpd2.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_DIR="${ROOT_DIR}/lab"
OUT_DIR="${LAB_DIR}/out"
KEYS_DIR="${LAB_DIR}/keys"

# Prefer Rancher Desktop locally; do not override DOCKER_HOST in CI/GHA/act.
if [[ -z "${DOCKER_HOST:-}" && "${CI:-}" != "true" && -z "${GITHUB_ACTIONS:-}" ]]; then
  export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"
fi
# Prefer deterministic single-manifest images for clearer build-info + layer demos.
# Provenance attestations remain available via jf evd create in this lab.
export BUILDX_NO_DEFAULT_ATTESTATIONS="${BUILDX_NO_DEFAULT_ATTESTATIONS:-1}"

SERVER_ID="${SERVER_ID:-tomjpd2}"
JF_URL="${JF_URL:-https://tomjpd2.jfrog.io}"
DOCKER_REPO="${DOCKER_REPO:-lineage-docker-local}"
REGISTRY_HOST="${REGISTRY_HOST:-tomjpd2.jfrog.io}"

# Child unique tags: <stable>-<GITHUB_RUN_NUMBER> when UNIQUE_IMAGE_TAGS=1 (publish
# jobs only). Detector / Dockerfile FROM / AppTrust keep the stable aliases.
child_image_tag() {
  local stable="$1"
  if [[ "${UNIQUE_IMAGE_TAGS:-}" == "1" && -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    printf '%s-%s\n' "${stable}" "${GITHUB_RUN_NUMBER}"
  else
    printf '%s\n' "${stable}"
  fi
}

# Image names used in the lab:
#   golden-base (APP base), payments-api (direct descendant), salestax-api (multi-hop)
GOLDEN_NAME="${GOLDEN_NAME:-golden-base}"
GOLDEN_TAG="${GOLDEN_TAG:-1.0.0}"
APP_NAME="${APP_NAME:-payments-api}"
APP_TAG_STABLE="${APP_TAG_STABLE:-2.0.0}"
APP_TAG="${APP_TAG:-$(child_image_tag "${APP_TAG_STABLE}")}"
APP_RENAMED_NAME="${APP_RENAMED_NAME:-billing-service}"
APP_RENAMED_TAG_STABLE="${APP_RENAMED_TAG_STABLE:-9.9.9}"
APP_RENAMED_TAG="${APP_RENAMED_TAG:-$(child_image_tag "${APP_RENAMED_TAG_STABLE}")}"
# Multi-hop: FROM payments-api, not directly FROM golden-base
SALESTAX_NAME="${SALESTAX_NAME:-salestax-api}"
SALESTAX_TAG_STABLE="${SALESTAX_TAG_STABLE:-0.1.0}"
SALESTAX_TAG="${SALESTAX_TAG:-$(child_image_tag "${SALESTAX_TAG_STABLE}")}"
NON_GOLDEN_NAME="${NON_GOLDEN_NAME:-rogue-api}"
NON_GOLDEN_TAG_STABLE="${NON_GOLDEN_TAG_STABLE:-1.0.0}"
NON_GOLDEN_TAG="${NON_GOLDEN_TAG:-$(child_image_tag "${NON_GOLDEN_TAG_STABLE}")}"

KEY_ALIAS="${KEY_ALIAS:-acme-lineage-lab}"
KEY_FILE="${KEYS_DIR}/evidence.key"

GOLDEN_IMAGE="${REGISTRY_HOST}/${DOCKER_REPO}/${GOLDEN_NAME}:${GOLDEN_TAG}"
APP_IMAGE="${REGISTRY_HOST}/${DOCKER_REPO}/${APP_NAME}:${APP_TAG}"
APP_IMAGE_STABLE="${REGISTRY_HOST}/${DOCKER_REPO}/${APP_NAME}:${APP_TAG_STABLE}"
APP_RENAMED_IMAGE="${REGISTRY_HOST}/${DOCKER_REPO}/${APP_RENAMED_NAME}:${APP_RENAMED_TAG}"
APP_RENAMED_IMAGE_STABLE="${REGISTRY_HOST}/${DOCKER_REPO}/${APP_RENAMED_NAME}:${APP_RENAMED_TAG_STABLE}"
SALESTAX_IMAGE="${REGISTRY_HOST}/${DOCKER_REPO}/${SALESTAX_NAME}:${SALESTAX_TAG}"
SALESTAX_IMAGE_STABLE="${REGISTRY_HOST}/${DOCKER_REPO}/${SALESTAX_NAME}:${SALESTAX_TAG_STABLE}"
NON_GOLDEN_IMAGE="${REGISTRY_HOST}/${DOCKER_REPO}/${NON_GOLDEN_NAME}:${NON_GOLDEN_TAG}"
NON_GOLDEN_IMAGE_STABLE="${REGISTRY_HOST}/${DOCKER_REPO}/${NON_GOLDEN_NAME}:${NON_GOLDEN_TAG_STABLE}"

# Extra registry tag so catalog-native FROM / detector still use the stable alias.
push_stable_alias() {
  local unique_image="$1"
  local stable_image="$2"
  [[ "${unique_image}" == "${stable_image}" ]] && return 0
  log "Also tag catalog alias ${stable_image}"
  docker tag "${unique_image}" "${stable_image}"
  jf docker push "${stable_image}" --server-id "${SERVER_ID}"
}

PREDICATE_TYPE_GOLDEN="https://jfrog.com/evidence/acme-docker-lineage/golden-base/v1"
PREDICATE_TYPE_LINEAGE="https://jfrog.com/evidence/acme-docker-lineage/derived-from/v1"

mkdir -p "${OUT_DIR}" "${KEYS_DIR}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# A deactivated SaaS instance 302s everything to the landing page, which answers
# 200 with HTML. Without this check, callers "succeed" and jq dies on <!DOCTYPE.
require_platform() {
  local ping
  ping="$(jf rt ping --server-id "${SERVER_ID}" 2>&1)"
  [[ "${ping}" == *OK* ]] && return 0
  if [[ "${ping}" == *"JFrog Landing"* || "${ping}" == *"<!DOCTYPE html>"* ]]; then
    die "${JF_URL:-platform} is deactivated (serving the JFrog landing page). Reactivate at https://landing.jfrog.com/reactivate-server/<instance> and re-run."
  fi
  die "jf rt ping failed for server-id ${SERVER_ID}: $(printf '%s' "${ping}" | head -3)"
}

image_digest() {
  local image="$1"
  docker image inspect --format '{{index .RepoDigests 0}}' "${image}" 2>/dev/null \
    | sed -E 's/.*@//' \
    || true
}

# Ordered compressed layer digests from the local image config/manifest via docker.
# Uses RootFS.Layers (DiffIDs). For cross-image prefix matching after docker build
# FROM, DiffIDs of the base are a prefix of the child DiffIDs.
layer_diff_ids() {
  local image="$1"
  docker image inspect --format '{{json .RootFS.Layers}}' "${image}" | jq -r '.[]'
}

write_layers_file() {
  local image="$1"
  local out="$2"
  layer_diff_ids "${image}" > "${out}"
}

manifest_list_or_manifest_path() {
  # Artifactory Docker layout: <repo>/<name>/<tag>/manifest.json
  local name="$1" tag="$2"
  echo "${DOCKER_REPO}/${name}/${tag}/manifest.json"
}
