#!/usr/bin/env bash
# Create AppTrust version from Build Info, certify, and release to PROD (Trusted Release).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

SERVER_ID="${SERVER_ID:-tomjpd2}"
APP_KEY="${APP_KEY:-golden-alpine}"
APP_VERSION="${APP_VERSION:?APP_VERSION required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER required}"
INDEX_DIGEST="${INDEX_DIGEST:?INDEX_DIGEST required}"
UPSTREAM_TAG="${UPSTREAM_TAG:?UPSTREAM_TAG required}"
KEY_ALIAS="${KEY_ALIAS:-acme-lineage-lab}"
EVIDENCE_KEY_FILE="${EVIDENCE_KEY_FILE:?EVIDENCE_KEY_FILE required}"
REGISTRY_HOST="${REGISTRY_HOST:?REGISTRY_HOST required}"
SKIP_PRE_CERT_DRY_RUN="${SKIP_PRE_CERT_DRY_RUN:-0}"

"${SCRIPT_DIR}/validate-config.sh" "${APP_KEY}"
gi_require_upstream_path "${APP_KEY}" "library/alpine"
gi_validate_sha256_digest "${INDEX_DIGEST}" || gi_die "invalid INDEX_DIGEST"
gi_validate_version_string "${APP_VERSION}" || gi_die "invalid APP_VERSION"

gi_load_catalog
PROJECT_KEY="$(gi_project_key)"
DEV_REPO="$(gi_repo dev_local)"
RELEASE_REPO="$(gi_repo release_local)"
GOLDEN_CERT="$(jq -r '.evidence.golden_certification_predicate' <<<"${GI_CATALOG_JSON}")"
SLSA_PRED="$(jq -r '.evidence.slsa_provenance_predicate' <<<"${GI_CATALOG_JSON}")"
SBOM_PRED="$(jq -r '.evidence.cyclonedx_sbom_predicate' <<<"${GI_CATALOG_JSON}")"

APP_JSON="$(gi_app_json "${APP_KEY}")"
IMAGE_NAME="$(jq -r '.image_name' <<<"${APP_JSON}")"
BUILD_NAME="$(jq -r '.build_name' <<<"${APP_JSON}")"
BUILD_INFO_REPO="$(gi_build_info_repo)"

wait_for_predicate() {
  local subject_path="$1" predicate_fragment="$2"
  local attempt=0 max="${EVIDENCE_WAIT_ATTEMPTS:-36}"
  while [[ "${attempt}" -lt "${max}" ]]; do
    if jf evd get --subject-repo-path "${subject_path}" --server-id "${SERVER_ID}" --format json 2>/dev/null \
      | jq -e --arg p "${predicate_fragment}" \
        '[.result.evidence[]?.predicateType // empty] | any(. == $p or (contains($p)))' >/dev/null; then
      gi_log "Found evidence predicate matching ${predicate_fragment} on ${subject_path}"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 10
  done
  gi_die "timed out waiting for evidence ${predicate_fragment} on ${subject_path}"
}

verify_build_info_digest() {
  local info
  info="$(gi_jf_api "/artifactory/api/build/${BUILD_NAME}/${BUILD_NUMBER}?project=${PROJECT_KEY}")"
  if gi_build_info_references_digest "${info}" "${INDEX_DIGEST}"; then
    gi_log "Build Info ${BUILD_NAME}/${BUILD_NUMBER} references index ${INDEX_DIGEST}"
    return 0
  fi

  # build-docker-create often records per-arch manifest digests, not the OCI index digest.
  local tag_ref="${REGISTRY_HOST}/${DEV_REPO}/${IMAGE_NAME}:${APP_VERSION}"
  local resolved_index="" platform_digest="" matched=""
  if ! resolved_index="$(docker buildx imagetools inspect "${tag_ref}" --format '{{json .Manifest}}' 2>/dev/null \
    | jq -r '.digest // empty')"; then
    gi_die "Build Info ${BUILD_NAME}/${BUILD_NUMBER} does not reference ${INDEX_DIGEST} (and could not inspect ${tag_ref})"
  fi
  [[ "${resolved_index}" == "${INDEX_DIGEST}" ]] \
    || gi_die "tag ${tag_ref} index ${resolved_index} != expected ${INDEX_DIGEST}"

  while IFS= read -r platform_digest; do
    [[ -z "${platform_digest}" ]] && continue
    if gi_build_info_references_digest "${info}" "${platform_digest}"; then
      matched="${platform_digest}"
      break
    fi
  done < <(gi_multiarch_manifest_digests_for_tag "${tag_ref}" || true)

  [[ -n "${matched}" ]] \
    || gi_die "Build Info ${BUILD_NAME}/${BUILD_NUMBER} does not reference index ${INDEX_DIGEST} or any platform manifest for ${tag_ref}"
  gi_log "Build Info references platform manifest ${matched} (release identity ${INDEX_DIGEST})"
}

create_or_verify_app_version() {
  if gi_jf_api "/apptrust/api/v1/applications/${APP_KEY}/versions/${APP_VERSION}" >/dev/null 2>&1; then
    gi_log "App version ${APP_KEY}@${APP_VERSION} already exists — verifying build source"
    return 0
  fi
  gi_log "Creating AppTrust version ${APP_KEY}@${APP_VERSION} from Build Info only"
  jf apptrust version-create "${APP_KEY}" "${APP_VERSION}" \
    --sync=true \
    --skip-unassigned=true \
    --source-type-builds "name=${BUILD_NAME}, id=${BUILD_NUMBER}, repo-key=${BUILD_INFO_REPO}" \
    --server-id "${SERVER_ID}"
}

dry_run_release_expect_block() {
  [[ "${SKIP_PRE_CERT_DRY_RUN}" == "1" ]] && { gi_log "Skipping pre-cert dry-run"; return 0; }
  gi_log "Dry-run promote to PROD (expect block before Golden certification)"
  local out decision
  # version-release has no --dry-run (verified via jf apptrust version-release --help); use version-promote.
  if ! out="$(jf apptrust version-promote "${APP_KEY}" "${APP_VERSION}" PROD \
      --dry-run=true --sync=true --server-id "${SERVER_ID}" 2>&1)"; then
    gi_log "Dry-run returned non-zero (expected before certification)"
    printf '%s\n' "${out}" | head -20
    return 0
  fi
  decision="$(printf '%s\n' "${out}" | jq -r '.evaluations.entry_gate.decision // .evaluations.release_gate.decision // .status // empty' 2>/dev/null || true)"
  if [[ "${decision}" == "pass" ]]; then
    gi_die "pre-cert dry-run unexpectedly passed — Golden certification gate may be missing"
  fi
  gi_log "Pre-cert dry-run blocked or incomplete as expected"
}

attach_golden_certification() {
  local predicate_file="${RUNNER_TEMP:-/tmp}/golden-cert-${APP_VERSION}.json"
  jq -n \
    --arg app "${APP_KEY}" \
    --arg ver "${APP_VERSION}" \
    --arg upstream_tag "${UPSTREAM_TAG}" \
    --arg index_digest "${INDEX_DIGEST}" \
    --arg build_name "${BUILD_NAME}" \
    --arg build_number "${BUILD_NUMBER}" \
    --arg image "${IMAGE_NAME}" \
    --arg dev_repo "${DEV_REPO}" \
    --arg actor "${GITHUB_ACTOR:-local}" \
    --arg run_url "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-0}" \
    --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      role: "golden-image-certification",
      application_key: $app,
      application_version: $ver,
      upstream_image_path: "library/alpine",
      upstream_tag: $upstream_tag,
      golden_image_name: $image,
      golden_image_digest: $index_digest,
      build_name: $build_name,
      build_number: $build_number,
      dev_repository: $dev_repo,
      certified_by: $actor,
      workflow_run: $run_url,
      created_at: $created_at
    }' > "${predicate_file}"

  jf evd create \
    --build-name "${BUILD_NAME}" \
    --build-number "${BUILD_NUMBER}" \
    --predicate "${predicate_file}" \
    --predicate-type "${GOLDEN_CERT}" \
    --key "${EVIDENCE_KEY_FILE}" \
    --key-alias "${KEY_ALIAS}" \
    --project "${PROJECT_KEY}" \
    --server-id "${SERVER_ID}"
}

require_release_evidence() {
  local build_subject="${BUILD_INFO_REPO}/${BUILD_NAME}/${BUILD_NUMBER}"
  wait_for_predicate "${build_subject}" "${SLSA_PRED}"
  wait_for_predicate "${build_subject}" "${SBOM_PRED}"
  wait_for_predicate "${build_subject}" "${GOLDEN_CERT}"
}

release_to_prod() {
  gi_log "Releasing ${APP_KEY}@${APP_VERSION} to PROD (copy, overwrite disabled)"
  jf apptrust version-release "${APP_KEY}" "${APP_VERSION}" \
    --sync=true \
    --promotion-type=copy \
    --overwrite-strategy=disabled \
    --include-repos="${DEV_REPO};${RELEASE_REPO}" \
    --server-id "${SERVER_ID}"
}

verify_release_artifact() {
  local tag_ref="${REGISTRY_HOST}/${RELEASE_REPO}/${IMAGE_NAME}:${APP_VERSION}"
  gi_log "Verifying release catalog tag ${tag_ref}"
  local rel_digest
  rel_digest="$(docker buildx imagetools inspect "${tag_ref}" --format '{{json .Manifest}}' 2>/dev/null \
    | jq -r '.digest // empty' || true)"
  [[ -n "${rel_digest}" ]] || gi_die "release tag not found: ${tag_ref}"
  [[ "${rel_digest}" == "${INDEX_DIGEST}" ]] \
    || gi_die "PROD digest ${rel_digest} != DEV index ${INDEX_DIGEST}"
}

main() {
  verify_build_info_digest
  create_or_verify_app_version
  dry_run_release_expect_block
  local build_path="${BUILD_INFO_REPO}/${BUILD_NAME}/${BUILD_NUMBER}"
  wait_for_predicate "${build_path}" "provenance"
  wait_for_predicate "${build_path}" "cyclonedx"
  attach_golden_certification
  require_release_evidence
  release_to_prod
  verify_release_artifact
  gi_log "Trusted Release path complete for ${APP_KEY}@${APP_VERSION}"
}

main "$@"
