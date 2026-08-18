#!/usr/bin/env bash
# Shared bootstrap for lab/scripts/steps/* (does not replace 01-build-push.sh).
# shellcheck shell=bash
set -euo pipefail

STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${STEPS_DIR}/.." && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd docker
require_cmd jf
require_cmd jq

# RUN_ID / BUILD_NUM chain artifacts across manually dispatched workflows.
BUILD_NUM="${BUILD_NUM:-${RUN_ID:-$(date +%Y%m%d%H%M%S)}}"
RUN_ID="${RUN_ID:-${BUILD_NUM}}"
RUN_STAMP="${RUN_ID}"
RUN_DIR="${OUT_DIR}/${RUN_STAMP}"
mkdir -p "${RUN_DIR}"
echo "${RUN_STAMP}" > "${OUT_DIR}/latest-run.txt"
export BUILD_NUM RUN_ID RUN_STAMP RUN_DIR

ensure_docker_login() {
  log "Docker login to ${REGISTRY_HOST}"
  jf docker login "${REGISTRY_HOST}" --server-id "${SERVER_ID}"
}
