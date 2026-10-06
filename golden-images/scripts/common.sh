#!/usr/bin/env bash
# Shared helpers for Golden Image Management (golden-images project).
set -euo pipefail

GI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GI_REPO_ROOT="$(cd "${GI_ROOT}/.." && pwd)"
GI_CATALOG="${GI_CATALOG:-${GI_ROOT}/catalog.json}"
GI_INVENTORY="${GI_INVENTORY:-${GI_ROOT}/platform-inventory.json}"

gi_die() { echo "golden-images: $*" >&2; exit 1; }
gi_log() { printf '==> %s\n' "$*" >&2; }

gi_require_tools() {
  command -v jq >/dev/null 2>&1 || gi_die "jq is required"
}

gi_load_catalog() {
  gi_require_tools
  [[ -f "${GI_CATALOG}" ]] || gi_die "catalog not found: ${GI_CATALOG}"
  GI_CATALOG_JSON="$(cat "${GI_CATALOG}")"
  export GI_CATALOG_JSON
}

gi_load_inventory() {
  gi_require_tools
  [[ -f "${GI_INVENTORY}" ]] || gi_die "platform inventory not found: ${GI_INVENTORY}"
  GI_INVENTORY_JSON="$(cat "${GI_INVENTORY}")"
  export GI_INVENTORY_JSON
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

# Normalized sha256:… digests from build-info (CLI uses bare hex in artifacts[].sha256).
gi_build_info_sha256_strings() {
  local info_json="$1"
  jq -r '
    def as_digest:
      if test("^sha256:[a-f0-9]{64}$") then .
      elif test("^[a-f0-9]{64}$") then "sha256:\(.)"
      elif test("sha256:[a-f0-9]{64}") then match("sha256:[a-f0-9]{64}").string
      else empty
      end;
    [ .. | strings | as_digest | select(. != null and length > 0) ] | unique[] | select(length > 0)
  ' <<<"${info_json}"
}

# True when build-info JSON mentions a digest (index or platform manifest).
gi_build_info_references_digest() {
  local info_json="$1" digest="$2"
  gi_build_info_sha256_strings "${info_json}" | grep -Fqx "${digest}"
}

gi_build_info_references_any_digest() {
  local info_json="$1" digest
  shift
  for digest in "$@"; do
    if gi_build_info_references_digest "${info_json}" "${digest}"; then
      printf '%s\n' "${digest}"
      return 0
    fi
  done
  return 1
}

# Index + linux platform image manifest digests for a multi-arch tag (excludes attestations).
gi_multiarch_manifest_digests_for_tag() {
  local tag_ref="$1"
  local manifest_json
  manifest_json="$(docker buildx imagetools inspect "${tag_ref}" --format '{{json .Manifest}}' 2>/dev/null)" \
    || return 1
  jq -r '
    .digest,
    (.manifests[]?
      | select((.annotations["vnd.docker.reference.type"] // "") != "attestation-manifest")
      | select(.platform.os != "unknown")
      | .digest)
  ' <<<"${manifest_json}" | awk 'NF && !seen[$0]++'
}

# JFrog REST via `jf api` (lab convention: options first, path last, body via --input).
gi_jf_api() {
  local server_id="${SERVER_ID:-tomjpd2}"
  command -v jf >/dev/null 2>&1 || gi_die "jf (JFrog CLI) is required"
  if ! jf api --help >/dev/null 2>&1; then
    gi_die "jf api is required (JFrog CLI >= 2.120; see setup-jfrog-cli in workflows)"
  fi
  local timeout_args=()
  if [[ -n "${GI_JF_HTTP_TIMEOUT:-}" ]]; then
    timeout_args=(--timeout "${GI_JF_HTTP_TIMEOUT}")
  fi
  jf api --server-id "${server_id}" "${timeout_args[@]}" "$@"
}

gi_jf_resource_exists() {
  local path="$1"
  gi_jf_api "${path}" >/dev/null 2>&1
}

# Like gi_jf_request_json but returns non-zero without dying (for create + conflict handling).
gi_jf_request_json_try() {
  local method="$1" path="$2" body="$3"
  local tmp err out rc
  tmp="$(mktemp)"
  err="$(mktemp)"
  printf '%s' "${body}" > "${tmp}"
  set +e
  out="$(gi_jf_api -X "${method}" -H "Content-Type: application/json" --input "${tmp}" "${path}" 2>"${err}")"
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    GI_JF_LAST_API_ERROR="$(tr -d '\n' <"${err}") ${out}"
    export GI_JF_LAST_API_ERROR
  else
    GI_JF_LAST_API_ERROR=""
    export GI_JF_LAST_API_ERROR
  fi
  rm -f "${tmp}" "${err}"
  [[ "${rc}" -eq 0 ]] && printf '%s' "${out}"
  return "${rc}"
}

# Transient Unified Policy 500s: retry with longer HTTP timeout (jf default can be 0).
gi_jf_request_json_retry() {
  local method="$1" path="$2" body="$3" attempts="${4:-5}"
  local n=1 out
  while [[ "${n}" -le "${attempts}" ]]; do
    if out="$(GI_JF_HTTP_TIMEOUT="${GI_JF_HTTP_TIMEOUT:-120}" gi_jf_request_json_try "${method}" "${path}" "${body}")"; then
      printf '%s' "${out}"
      return 0
    fi
    if [[ "${n}" -lt "${attempts}" ]]; then
      gi_log "jf api ${method} ${path} failed (attempt ${n}/${attempts}), retrying…"
      sleep 3
    fi
    n=$((n + 1))
  done
  return 1
}

gi_jf_request_json() {
  local method="$1" path="$2" body="$3" out
  if ! out="$(gi_jf_request_json_try "${method}" "${path}" "${body}")"; then
    gi_die "jf api ${method} ${path} failed"
  fi
  printf '%s' "${out}"
}

gi_json_equal() {
  local a="$1" b="$2"
  [[ "$(jq -cS . <<<"${a}")" == "$(jq -cS . <<<"${b}")" ]]
}

# Unified Policy list responses: never use (.items // .)[] on a bare object — that
# iterates object values and breaks on .id (strings). Only .items[] or a top-level array.
gi_up_entity_id_by_name() {
  local json="$1" name="$2"
  jq -r --arg n "${name}" '
    def entity_list:
      if type == "array" then .
      elif type == "object" and (.items | type) == "array" then .items
      else [] end;
    entity_list[]
    | select(type == "object" and .name == $n)
    | .id // empty
    | select(length > 0)
  ' <<<"${json}" | head -1
}

gi_up_rule_predicate_by_name() {
  local json="$1" name="$2"
  jq -r --arg n "${name}" '
    def entity_list:
      if type == "array" then .
      elif type == "object" and (.items | type) == "array" then .items
      else [] end;
    entity_list[]
    | select(type == "object" and .name == $n)
    | (.parameters // [])[]
    | select(.name == "predicateType")
    | .value // empty
  ' <<<"${json}" | head -1
}

# Create responses may be {"id":"…"} or a JSON string id.
gi_up_response_id() {
  local json="$1"
  jq -r '
    if type == "object" then .id // .rule_id // .policy_id // empty
    elif type == "string" then .
    else empty end
  ' <<<"${json}" | head -1
}
