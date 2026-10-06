#!/usr/bin/env bash
# Shared helpers for Golden Image Management (golden-images project).
set -euo pipefail

GI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GI_REPO_ROOT="$(cd "${GI_ROOT}/.." && pwd)"
GI_CATALOG="${GI_CATALOG:-${GI_ROOT}/catalog.json}"

gi_die() { echo "golden-images: $*" >&2; exit 1; }
gi_log() { printf '==> %s\n' "$*"; }

gi_require_tools() {
  command -v jq >/dev/null 2>&1 || gi_die "jq is required"
}

gi_load_catalog() {
  gi_require_tools
  [[ -f "${GI_CATALOG}" ]] || gi_die "catalog not found: ${GI_CATALOG}"
  GI_CATALOG_JSON="$(cat "${GI_CATALOG}")"
  export GI_CATALOG_JSON
}

gi_project_key() {
  gi_load_catalog
  jq -r '.project_key' <<<"${GI_CATALOG_JSON}"
}

gi_validate_sha256_digest() {
  local digest="$1"
  [[ "${digest}" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
}

gi_validate_version_string() {
  local ver="$1"
  [[ -n "${ver}" ]] || return 1
  [[ "${ver}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$ ]] || return 1
}

gi_app_json() {
  local app_key="$1"
  gi_load_catalog
  local app
  app="$(jq -c --arg k "${app_key}" '.applications[] | select(.application_key == $k)' <<<"${GI_CATALOG_JSON}")"
  [[ -n "${app}" ]] || gi_die "unknown application_key: ${app_key}"
  printf '%s\n' "${app}"
}

gi_upstream_path_for_app() {
  jq -r '.upstream_image_path' <<<"$(gi_app_json "$1")"
}

gi_assert_upstream_path() {
  local app_key="$1" path="$2"
  local expected
  expected="$(gi_upstream_path_for_app "${app_key}")"
  [[ "${path}" == "${expected}" ]]
}

gi_require_upstream_path() {
  local app_key="$1" path="$2"
  gi_assert_upstream_path "${app_key}" "${path}" \
    || gi_die "upstream path must be $(gi_upstream_path_for_app "${app_key}"), got ${path}"
}

gi_repo() {
  local which="$1"
  gi_load_catalog
  jq -r --arg w "${which}" '.repos[$w]' <<<"${GI_CATALOG_JSON}"
}

gi_build_info_repo() {
  printf '%s-build-info\n' "$(gi_project_key)"
}
