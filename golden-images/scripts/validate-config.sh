#!/usr/bin/env bash
# Validate golden-images/catalog.json and optional application key argument.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

APP_KEY="${1:-}"

gi_load_catalog

keys="$(jq -r '.applications[].application_key' <<<"${GI_CATALOG_JSON}")"
if [[ "$(printf '%s\n' ${keys} | sort | uniq -d | wc -l | tr -d ' ')" != "0" ]]; then
  gi_die "duplicate application_key in catalog"
fi

if jq -e '.lifecycle.promote_stages[]? | select(. == "PROD")' <<<"${GI_CATALOG_JSON}" >/dev/null 2>&1; then
  gi_die "lifecycle.promote_stages must not include PROD (global release stage, not promote)"
fi

for key in upstream_remote dev_local release_local; do
  val="$(jq -r --arg k "${key}" '.repos[$k] // empty' <<<"${GI_CATALOG_JSON}")"
  [[ -n "${val}" ]] || gi_die "repos.${key} is required"
  [[ "${val}" =~ ^[a-z0-9][a-z0-9-]{1,62}$ ]] || gi_die "invalid repo key: ${val}"
done

jq -c '.applications[]' <<<"${GI_CATALOG_JSON}" | while read -r app; do
  for field in application_key upstream_image_path image_name build_name dockerfile build_context; do
    v="$(jq -r --arg f "${field}" '.[$f] // empty' <<<"${app}")"
    [[ -n "${v}" ]] || gi_die "applications[].${field} is required"
  done
  path="$(jq -r '.upstream_image_path' <<<"${app}")"
  [[ "${path}" != *" "* ]] || gi_die "upstream_image_path must not contain spaces"
done

if [[ -n "${APP_KEY}" ]]; then
  gi_app_json "${APP_KEY}" >/dev/null
fi

gi_log "catalog OK${APP_KEY:+ for ${APP_KEY}}"
