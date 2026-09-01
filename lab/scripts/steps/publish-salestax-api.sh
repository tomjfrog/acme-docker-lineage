#!/usr/bin/env bash
# Publish salestax-api FROM payments-api; Evidence names immediate parent only.
# Copied from lab/scripts/01-build-push.sh section 3 — original 01 left intact.
set -euo pipefail
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

if [[ -f "${RUN_DIR}/app.digest.txt" ]]; then
  APP_DIGEST="$(cat "${RUN_DIR}/app.digest.txt")"
else
  log "No local app.digest.txt — pulling ${APP_IMAGE} for digest"
  docker pull "${APP_IMAGE}"
  APP_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${APP_IMAGE}" | sed -E 's/.*@//')"
  mkdir -p "${RUN_DIR}"
  printf '%s\n' "${APP_DIGEST}" > "${RUN_DIR}/app.digest.txt"
  printf '%s\n' "${APP_IMAGE}" > "${RUN_DIR}/app.ref.txt"
fi

log "Build multi-hop salestax-api → ${SALESTAX_IMAGE} (FROM ${APP_IMAGE})"
docker build \
  --build-arg "BASE_IMAGE=${APP_IMAGE}" \
  -t "${SALESTAX_IMAGE}" \
  "${LAB_DIR}/app-from-intermediate"

log "Push salestax-api with build-info"
jf docker push "${SALESTAX_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-salestax" \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env "acme-lineage-salestax" "${BUILD_NUM}" || true
jf rt build-publish "acme-lineage-salestax" "${BUILD_NUM}" --server-id "${SERVER_ID}"

SALESTAX_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${SALESTAX_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${SALESTAX_IMAGE}" "${RUN_DIR}/salestax.layers.txt"
printf '%s\n' "${SALESTAX_DIGEST}" > "${RUN_DIR}/salestax.digest.txt"
printf '%s\n' "${SALESTAX_IMAGE}" > "${RUN_DIR}/salestax.ref.txt"

cat > "${RUN_DIR}/salestax-lineage-evidence.json" <<EOF
{
  "role": "derived-image",
  "image_ref": "${SALESTAX_IMAGE}",
  "image_digest": "${SALESTAX_DIGEST}",
  "base_image_ref": "${APP_IMAGE}",
  "base_image_digest": "${APP_DIGEST}",
  "base_package_name": "${APP_NAME}",
  "base_package_version": "${APP_TAG}",
  "derived_from_golden": false,
  "immediate_parent_only": true,
  "note": "Immediate base is payments-api, not golden-base. Root golden requires Evidence walk or layer-prefix.",
  "lab": "acme-docker-lineage",
  "build_name": "acme-lineage-salestax",
  "build_number": "${BUILD_NUM}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

log "Attach lineage Evidence to salestax-api (immediate parent = payments-api only)"
jf evd create \
  --server-id "${SERVER_ID}" \
  --package-name "${SALESTAX_NAME}" \
  --package-version "${SALESTAX_TAG}" \
  --package-repo-name "${DOCKER_REPO}" \
  --predicate "${RUN_DIR}/salestax-lineage-evidence.json" \
  --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
  --key "${KEY_FILE}" \
  --key-alias "${KEY_ALIAS}" \
  | tee "${RUN_DIR}/salestax-evidence-create.json" || {
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${SALESTAX_NAME}/${SALESTAX_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/salestax-lineage-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      | tee "${RUN_DIR}/salestax-evidence-create.json"
  }

log "salestax-api published. RUN_ID=${RUN_ID} digest=${SALESTAX_DIGEST}"
