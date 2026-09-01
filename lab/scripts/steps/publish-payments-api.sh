#!/usr/bin/env bash
# Publish payments-api FROM golden + lineage Evidence.
# Copied from lab/scripts/01-build-push.sh section 2 — original 01 left intact.
set -euo pipefail
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

if [[ -f "${RUN_DIR}/golden.digest.txt" ]]; then
  GOLDEN_DIGEST="$(cat "${RUN_DIR}/golden.digest.txt")"
else
  log "No local golden.digest.txt — pulling ${GOLDEN_IMAGE} for digest"
  docker pull "${GOLDEN_IMAGE}"
  GOLDEN_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${GOLDEN_IMAGE}" | sed -E 's/.*@//')"
  mkdir -p "${RUN_DIR}"
  printf '%s\n' "${GOLDEN_DIGEST}" > "${RUN_DIR}/golden.digest.txt"
  printf '%s\n' "${GOLDEN_IMAGE}" > "${RUN_DIR}/golden.ref.txt"
fi

log "Build app-from-golden → ${APP_IMAGE}"
docker build \
  --build-arg "GOLDEN_IMAGE=${GOLDEN_IMAGE}" \
  -t "${APP_IMAGE}" \
  "${LAB_DIR}/app-from-golden"

log "Push app-from-golden with build-info"
jf docker push "${APP_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-app" \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env "acme-lineage-app" "${BUILD_NUM}" || true
jf rt build-publish "acme-lineage-app" "${BUILD_NUM}" --server-id "${SERVER_ID}"

APP_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${APP_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${APP_IMAGE}" "${RUN_DIR}/app.layers.txt"
printf '%s\n' "${APP_DIGEST}" > "${RUN_DIR}/app.digest.txt"
printf '%s\n' "${APP_IMAGE}" > "${RUN_DIR}/app.ref.txt"

cat > "${RUN_DIR}/app-lineage-evidence.json" <<EOF
{
  "role": "derived-image",
  "image_ref": "${APP_IMAGE}",
  "image_digest": "${APP_DIGEST}",
  "base_image_ref": "${GOLDEN_IMAGE}",
  "base_image_digest": "${GOLDEN_DIGEST}",
  "base_package_name": "${GOLDEN_NAME}",
  "base_package_version": "${GOLDEN_TAG}",
  "derived_from_golden": true,
  "lab": "acme-docker-lineage",
  "build_name": "acme-lineage-app",
  "build_number": "${BUILD_NUM}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

log "Attach lineage Evidence to app package"
jf evd create \
  --server-id "${SERVER_ID}" \
  --package-name "${APP_NAME}" \
  --package-version "${APP_TAG}" \
  --package-repo-name "${DOCKER_REPO}" \
  --predicate "${RUN_DIR}/app-lineage-evidence.json" \
  --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
  --key "${KEY_FILE}" \
  --key-alias "${KEY_ALIAS}" \
  | tee "${RUN_DIR}/app-evidence-create.json" || {
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${APP_NAME}/${APP_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/app-lineage-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      | tee "${RUN_DIR}/app-evidence-create.json"
  }

log "payments-api published. RUN_ID=${RUN_ID} digest=${APP_DIGEST}"
