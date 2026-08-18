#!/usr/bin/env bash
# Publish Foo (golden-base): build, push, Build Info, properties, Evidence.
# Copied from lab/scripts/01-build-push.sh section 1 — original 01 left intact.
set -euo pipefail
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${STEPS_DIR}/_common.sh"

ensure_docker_login

log "Build golden base → ${GOLDEN_IMAGE}"
docker build -t "${GOLDEN_IMAGE}" "${LAB_DIR}/golden"

log "Push golden with build-info"
jf docker push "${GOLDEN_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-golden" \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env "acme-lineage-golden" "${BUILD_NUM}" || true
jf rt build-publish "acme-lineage-golden" "${BUILD_NUM}" --server-id "${SERVER_ID}"

GOLDEN_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${GOLDEN_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${GOLDEN_IMAGE}" "${RUN_DIR}/golden.layers.txt"
printf '%s\n' "${GOLDEN_DIGEST}" > "${RUN_DIR}/golden.digest.txt"
printf '%s\n' "${GOLDEN_IMAGE}" > "${RUN_DIR}/golden.ref.txt"

log "Set golden properties on ${DOCKER_REPO}/${GOLDEN_NAME}/${GOLDEN_TAG}/"
jf_rt set-props \
  "${DOCKER_REPO}/${GOLDEN_NAME}/${GOLDEN_TAG}/" \
  "golden.image=true;com.acme.image.role=golden-base;com.acme.lineage.lab=true"

cat > "${RUN_DIR}/golden-evidence.json" <<EOF
{
  "role": "golden-base",
  "image_ref": "${GOLDEN_IMAGE}",
  "image_digest": "${GOLDEN_DIGEST}",
  "approved": true,
  "lab": "acme-docker-lineage",
  "build_name": "acme-lineage-golden",
  "build_number": "${BUILD_NUM}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

log "Attach golden Evidence"
jf evd create \
  --server-id "${SERVER_ID}" \
  --package-name "${GOLDEN_NAME}" \
  --package-version "${GOLDEN_TAG}" \
  --package-repo-name "${DOCKER_REPO}" \
  --predicate "${RUN_DIR}/golden-evidence.json" \
  --predicate-type "${PREDICATE_TYPE_GOLDEN}" \
  --key "${KEY_FILE}" \
  --key-alias "${KEY_ALIAS}" \
  --format json | tee "${RUN_DIR}/golden-evidence-create.json" || {
    log "WARN: package-scoped evidence failed; trying subject-repo-path"
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${GOLDEN_NAME}/${GOLDEN_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/golden-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_GOLDEN}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      --format json | tee "${RUN_DIR}/golden-evidence-create.json"
  }

log "Golden published. RUN_ID=${RUN_ID} digest=${GOLDEN_DIGEST}"
