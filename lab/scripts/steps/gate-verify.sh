#!/usr/bin/env bash
# Dry-run promote: payments-api must PASS, rogue-api must FAIL.
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
log "Dry-run promote verification"
dry_run_promote "${APP_KEY}" "${APP_VERSION}" pass
dry_run_promote "${NEG_APP_KEY}" "${NEG_APP_VERSION}" fail

log "Tier 3 gate verify OK — ${STAGE_KEY} ${GATE} (${POLICY_MODE}) requires ${PREDICATE_URI}"
