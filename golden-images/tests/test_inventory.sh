#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

gi_log "platform inventory"

gi_load_catalog
gi_load_inventory

assert_ok "inventory project matches catalog" test \
  "$(jq -r '.project_key' <<<"${GI_INVENTORY_JSON}")" = \
  "$(jq -r '.project_key' <<<"${GI_CATALOG_JSON}")"

assert_ok "inventory lists xray watches" test \
  "$(jq '.provisioned_resources.xray.watches | length' <<<"${GI_INVENTORY_JSON}")" -ge 2

assert_ok "catalog xray policy matches inventory" test \
  "$(jq -r '.xray.policy_name' <<<"${GI_CATALOG_JSON}")" = \
  "$(jq -r '.provisioned_resources.xray.policies[0].name' <<<"${GI_INVENTORY_JSON}")"

test_summary
