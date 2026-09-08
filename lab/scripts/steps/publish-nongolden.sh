#!/usr/bin/env bash
# Publish rogue-api (non-golden negative control).
# Copied from lab/scripts/01-build-push.sh section 5 — original 01 left intact.
set -euo pipefail
export UNIQUE_IMAGE_TAGS=1
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

log "Build non-golden → ${NON_GOLDEN_IMAGE}"
docker build \
  --build-arg "GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:-0}" \
  --build-arg "GITHUB_RUN_ID=${GITHUB_RUN_ID:-0}" \
  -t "${NON_GOLDEN_IMAGE}" \
  "${LAB_DIR}/app-non-golden"

log "Push non-golden with build-info"
jf docker push "${NON_GOLDEN_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-nongolden" \
  --build-number "${BUILD_NUM}"
push_stable_alias "${NON_GOLDEN_IMAGE}" "${NON_GOLDEN_IMAGE_STABLE}"

jf rt build-publish "acme-lineage-nongolden" "${BUILD_NUM}" --server-id "${SERVER_ID}"

NON_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${NON_GOLDEN_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${NON_GOLDEN_IMAGE}" "${RUN_DIR}/non-golden.layers.txt"
printf '%s\n' "${NON_DIGEST}" > "${RUN_DIR}/non-golden.digest.txt"
printf '%s\n' "${NON_GOLDEN_IMAGE}" > "${RUN_DIR}/non-golden.ref.txt"

log "Non-golden published. RUN_ID=${RUN_ID} digest=${NON_DIGEST}"
