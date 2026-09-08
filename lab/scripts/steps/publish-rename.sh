#!/usr/bin/env bash
# Retag/push payments-api as billing-service with no Build Info / Evidence (rename demo).
# Copied from lab/scripts/01-build-push.sh section 4 — original 01 left intact.
set -euo pipefail
export UNIQUE_IMAGE_TAGS=1
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

# Prefer the catalog alias from 02; unique payments-api tags still share that digest.
if ! docker image inspect "${APP_IMAGE_STABLE}" >/dev/null 2>&1; then
  log "Pulling ${APP_IMAGE_STABLE} for retag"
  docker pull "${APP_IMAGE_STABLE}"
fi

log "Retag app as renamed image → ${APP_RENAMED_IMAGE}"
docker tag "${APP_IMAGE_STABLE}" "${APP_RENAMED_IMAGE}"

log "Push renamed image (no build-info / evidence — simulates rename without CI cooperation)"
jf docker push "${APP_RENAMED_IMAGE}" --server-id "${SERVER_ID}"
push_stable_alias "${APP_RENAMED_IMAGE}" "${APP_RENAMED_IMAGE_STABLE}"

RENAMED_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${APP_RENAMED_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${APP_RENAMED_IMAGE}" "${RUN_DIR}/app-renamed.layers.txt"
printf '%s\n' "${RENAMED_DIGEST}" > "${RUN_DIR}/app-renamed.digest.txt"
printf '%s\n' "${APP_RENAMED_IMAGE}" > "${RUN_DIR}/app-renamed.ref.txt"

log "Rename published. RUN_ID=${RUN_ID} digest=${RENAMED_DIGEST}"
