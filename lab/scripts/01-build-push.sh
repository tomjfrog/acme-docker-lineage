#!/usr/bin/env bash
# Build golden / from-golden / renamed / non-golden images; push to tomjpd2 with
# Build Info and Evidence.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd docker
require_cmd jf
require_cmd jq

BUILD_NUM="${BUILD_NUM:-$(date +%Y%m%d%H%M%S)}"
RUN_STAMP="${BUILD_NUM}"
RUN_DIR="${OUT_DIR}/${RUN_STAMP}"
mkdir -p "${RUN_DIR}"
echo "${RUN_STAMP}" > "${OUT_DIR}/latest-run.txt"

# Ensure keys exist for evidence attach
"${SCRIPT_DIR}/00-gen-keys.sh"

log "Docker login to ${REGISTRY_HOST}"
jf docker login "${REGISTRY_HOST}" --server-id "${SERVER_ID}"

# ---------------------------------------------------------------------------
# 1) Golden base
# ---------------------------------------------------------------------------
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
  | tee "${RUN_DIR}/golden-evidence-create.json" || {
    log "WARN: package-scoped evidence failed; trying subject-repo-path"
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${GOLDEN_NAME}/${GOLDEN_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/golden-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_GOLDEN}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      | tee "${RUN_DIR}/golden-evidence-create.json"
  }

# ---------------------------------------------------------------------------
# 2) App FROM golden
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 3) Multi-hop grandchild: Fizz FROM payments-api, not directly FROM golden
#    Evidence intentionally records only the immediate parent (payments-api) — no root
#    golden digest — so detectors must walk Evidence or use layer-prefix for root.
# ---------------------------------------------------------------------------
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
  "note": "Immediate base is payments-api, not golden-base. Root golden requires Evidence walk or layer-prefix.",
  "lab": "acme-docker-lineage",
  "build_name": "acme-lineage-grandchild",
  "build_number": "${BUILD_NUM}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

log "Attach lineage Evidence to grandchild (immediate parent = payments-api only)"
jf evd create \
  --server-id "${SERVER_ID}" \
  --package-name "${GRANDCHILD_NAME}" \
  --package-version "${GRANDCHILD_TAG}" \
  --package-repo-name "${DOCKER_REPO}" \
  --predicate "${RUN_DIR}/grandchild-lineage-evidence.json" \
  --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
  --key "${KEY_FILE}" \
  --key-alias "${KEY_ALIAS}" \
  | tee "${RUN_DIR}/grandchild-evidence-create.json" || {
    jf evd create \
      --server-id "${SERVER_ID}" \
      --subject-repo-path "${DOCKER_REPO}/${GRANDCHILD_NAME}/${GRANDCHILD_TAG}/manifest.json" \
      --predicate "${RUN_DIR}/grandchild-lineage-evidence.json" \
      --predicate-type "${PREDICATE_TYPE_LINEAGE}" \
      --key "${KEY_FILE}" \
      --key-alias "${KEY_ALIAS}" \
      | tee "${RUN_DIR}/grandchild-evidence-create.json"
  }

# ---------------------------------------------------------------------------
# 4) Rename: retag same image under a different name (no rebuild)
# ---------------------------------------------------------------------------
log "Retag app as renamed image → ${APP_RENAMED_IMAGE}"
docker tag "${APP_IMAGE}" "${APP_RENAMED_IMAGE}"

log "Push renamed image (no build-info / evidence — simulates rename without CI cooperation)"
jf docker push "${APP_RENAMED_IMAGE}" --server-id "${SERVER_ID}"

RENAMED_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${APP_RENAMED_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${APP_RENAMED_IMAGE}" "${RUN_DIR}/app-renamed.layers.txt"
printf '%s\n' "${RENAMED_DIGEST}" > "${RUN_DIR}/app-renamed.digest.txt"
printf '%s\n' "${APP_RENAMED_IMAGE}" > "${RUN_DIR}/app-renamed.ref.txt"

# ---------------------------------------------------------------------------
# 5) Non-golden app
# ---------------------------------------------------------------------------
log "Build non-golden → ${NON_GOLDEN_IMAGE}"
docker build -t "${NON_GOLDEN_IMAGE}" "${LAB_DIR}/app-non-golden"

log "Push non-golden with build-info"
jf docker push "${NON_GOLDEN_IMAGE}" \
  --server-id "${SERVER_ID}" \
  --build-name "acme-lineage-nongolden" \
  --build-number "${BUILD_NUM}"

jf rt build-publish "acme-lineage-nongolden" "${BUILD_NUM}" --server-id "${SERVER_ID}"

NON_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "${NON_GOLDEN_IMAGE}" | sed -E 's/.*@//')"
write_layers_file "${NON_GOLDEN_IMAGE}" "${RUN_DIR}/non-golden.layers.txt"
printf '%s\n' "${NON_DIGEST}" > "${RUN_DIR}/non-golden.digest.txt"
printf '%s\n' "${NON_GOLDEN_IMAGE}" > "${RUN_DIR}/non-golden.ref.txt"

cat > "${RUN_DIR}/summary.json" <<EOF
{
  "run": "${RUN_STAMP}",
  "registry": "${REGISTRY_HOST}",
  "repo": "${DOCKER_REPO}",
  "spec_chain": "golden-base=${GOLDEN_NAME} → payments-api=${APP_NAME} → fizz-service=${GRANDCHILD_NAME}",
  "golden": {"ref": "${GOLDEN_IMAGE}", "digest": "${GOLDEN_DIGEST}"},
  "app": {"ref": "${APP_IMAGE}", "digest": "${APP_DIGEST}"},
  "grandchild": {"ref": "${GRANDCHILD_IMAGE}", "digest": "${GRANDCHILD_DIGEST}", "immediate_base": "${APP_IMAGE}"},
  "app_renamed": {"ref": "${APP_RENAMED_IMAGE}", "digest": "${RENAMED_DIGEST}"},
  "non_golden": {"ref": "${NON_GOLDEN_IMAGE}", "digest": "${NON_DIGEST}"}
}
EOF

log "Run artifacts written to ${RUN_DIR}"
cat "${RUN_DIR}/summary.json"
log "Done. Next: lab/scripts/02-detect-lineage.sh"
