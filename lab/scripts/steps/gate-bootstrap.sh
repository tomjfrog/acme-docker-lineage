#!/usr/bin/env bash
# Bootstrap project/stage/Unified Policy/AppTrust apps+versions (Tier 3).
# Additive wrapper; lab/scripts/03-apptrust-gate.sh remains the full local one-shot.
set -euo pipefail
STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${STEPS_DIR}/.." && pwd)"
# shellcheck source=../lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_cmd jq
require_cmd jf
# shellcheck source=_gate_lib.sh
source "${STEPS_DIR}/_gate_lib.sh"

log "Using lineage predicate URI: ${PREDICATE_URI}"

ensure_project
ensure_repo_in_project
ensure_stage
RULE_ID="$(ensure_rule)"
POLICY_ID="$(ensure_policy "${RULE_ID}")"
log "Rule=${RULE_ID} Policy=${POLICY_ID}"

ensure_app "${APP_KEY}" "Payments API"
ensure_app "${NEG_APP_KEY}" "Rogue API"
ensure_version "${APP_KEY}" "${APP_VERSION}" "${APP_NAME}" "${PKG_VERSION}"
ensure_version "${NEG_APP_KEY}" "${NEG_APP_VERSION}" "${NON_GOLDEN_NAME}" "${NEG_PKG_VERSION}"

log "Gate bootstrap OK — ${STAGE_KEY} ${GATE} (${POLICY_MODE}) requires ${PREDICATE_URI}"
