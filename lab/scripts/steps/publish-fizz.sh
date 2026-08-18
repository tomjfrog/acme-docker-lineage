#!/usr/bin/env bash
# Publish Fizz (fizz-service) FROM Bar; Evidence names immediate parent only.
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

log "Build multi-hop grandchild → ${GRANDCHILD_IMAGE} (FROM ${APP_IMAGE})"
docker build \
  --build-arg "BASE_IMAGE=${APP_IMAGE}" \
  -t "${GRANDCHILD_IMAGE}" \
  "${LAB_DIR}/app-from-intermediate"

log "Push grandchild with build-info"
jf docker push "${GRANDCHILD_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-grandchild" \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env "acme-lineage-grandchild" "${BUILD_NUM}" || true
jf rt build-publish "acme-lineage-grandchild" "${BUILD_NUM}" --server-id "${SERVER_ID}"

GRANDCHILD_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${GRANDCHILD_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${GRANDCHILD_IMAGE}" "${RUN_DIR}/grandchild.layers.txt"
printf '%s\n' "${GRANDCHILD_DIGEST}" > "${RUN_DIR}/grandchild.digest.txt"
printf '%s\n' "${GRANDCHILD_IMAGE}" > "${RUN_DIR}/grandchild.ref.txt"

jf_rt set-props \
  "${DOCKER_REPO}/${GRANDCHILD_NAME}/${GRANDCHILD_TAG}/" \
  "golden.image=false;com.acme.image.role=app-multihop;com.acme.expected.base=intermediate;com.acme.lineage.lab=true;com.acme.base.digest=${APP_DIGEST}"

cat > "${RUN_DIR}/grandchild-lineage-evidence.json" <<EOF
{
  "role": "derived-image",
  "image_ref": "${GRANDCHILD_IMAGE}",
  "image_digest": "${GRANDCHILD_DIGEST}",
  "base_image_ref": "${APP_IMAGE}",
  "base_image_digest": "${APP_DIGEST}",
  "base_package_name": "${APP_NAME}",
  "base_package_version": "${APP_TAG}",
  "derived_from_golden": false,
  "immediate_parent_only": true,
  "note": "Immediate base is Bar (payments-api), not golden Foo. Root golden requires Evidence walk or layer-prefix.",
  "lab": "acme-docker-lineage",
  "build_name": "acme-lineage-grandchild",
  "build_number": "${BUILD_NUM}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

log "Attach lineage Evidence to grandchild (immediate parent = Bar only)"
jf evd create \
  --server-id "${SERVER_ID}" \
  --package-name "${GRANDCHILD_NAME}" \
  --package-version "${GRANDCHILD_TAG}" \
  --package-repo-name "${DOCKER_REPO}" \
  --predicate "${RUN_DIR}/grandchild-lineage-evidence.json" \
  --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
  --key "${KEY_FILE}" \
  --key-alias "${KEY_ALIAS}" \
  --format json | tee "${RUN_DIR}/grandchild-evidence-create.json" || {
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${GRANDCHILD_NAME}/${GRANDCHILD_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/grandchild-lineage-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      --format json | tee "${RUN_DIR}/grandchild-evidence-create.json"
  }

log "Fizz published. RUN_ID=${RUN_ID} digest=${GRANDCHILD_DIGEST}"
