#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

gi_log "Unified Policy jq helpers"

assert_ok "find id in items array" test \
  "$(gi_up_entity_id_by_name '{"items":[{"name":"A","id":"id-a"}]}' 'A')" = "id-a"

assert_ok "find id in top-level array" test \
  "$(gi_up_entity_id_by_name '[{"name":"B","id":"id-b"}]' 'B')" = "id-b"

assert_ok "object root without items does not jq-fail" test \
  "$(gi_up_entity_id_by_name '{"name":"stray","id":"x"}' 'stray' || true)" = ""

assert_ok "response object id" test \
  "$(gi_up_response_id '{"id":"rule-1","name":"n"}')" = "rule-1"

assert_ok "response string id" test \
  "$(gi_up_response_id '"rule-2"')" = "rule-2"

test_summary
