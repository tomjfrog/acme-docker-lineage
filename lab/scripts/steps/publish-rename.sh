#!/usr/bin/env bash
# Retag/push payments-api as billing-service with no Build Info / Evidence (rename demo).
# Copied from lab/scripts/01-build-push.sh section 4 — original 01 left intact.
set -euo pipefail
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

# Prefer local image; otherwise pull payments-api from registry.
if ! docker image inspect "${APP_IMAGE}" >/dev/null 2>&1; then
  log "Pulling ${APP_IMAGE} for retag"
  docker pull "${APP_IMAGE}"
fi

log "Retag app as renamed image → ${APP_RENAMED_IMAGE}"
docker tag "${APP_IMAGE}" "${APP_RENAMED_IMAGE}"

log "Push renamed image (no build-info / evidence — simulates rename without CI cooperation)"
jf docker push "${APP_RENAMED_IMAGE}" --server-id "${SERVER_ID}"

RENAMED_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${APP_RENAMED_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${APP_RENAMED_IMAGE}" "${RUN_DIR}/app-renamed.layers.txt"
printf '%s\n' "${RENAMED_DIGEST}" > "${RUN_DIR}/app-renamed.digest.txt"
printf '%s\n' "${APP_RENAMED_IMAGE}" > "${RUN_DIR}/app-renamed.ref.txt"

jf_rt set-props \
  "${DOCKER_REPO}/${APP_RENAMED_NAME}/${APP_RENAMED_TAG}/" \
  "com.acme.image.role=app-renamed;com.acme.lineage.lab=true" || true

log "Rename published. RUN_ID=${RUN_ID} digest=${RENAMED_DIGEST}"
