#!/usr/bin/env bash
# Idempotent JFrog scaffolding for Golden Image Management project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

SERVER_ID="${SERVER_ID:-tomjpd2}"
DRY_RUN="${DRY_RUN:-0}"
APP_KEY="${1:-golden-alpine}"

"${SCRIPT_DIR}/validate-config.sh" "${APP_KEY}"

gi_load_catalog
PROJECT_KEY="$(gi_project_key)"
PROJECT_NAME="$(jq -r '.project_display_name' <<<"${GI_CATALOG_JSON}")"
UPSTREAM_REPO="$(gi_repo upstream_remote)"
DEV_REPO="$(gi_repo dev_local)"
RELEASE_REPO="$(gi_repo release_local)"
GOLDEN_CERT="$(jq -r '.evidence.golden_certification_predicate' <<<"${GI_CATALOG_JSON}")"
SLSA_PRED="$(jq -r '.evidence.slsa_provenance_predicate' <<<"${GI_CATALOG_JSON}")"
SBOM_PRED="$(jq -r '.evidence.cyclonedx_sbom_predicate' <<<"${GI_CATALOG_JSON}")"

APP_JSON="$(gi_app_json "${APP_KEY}")"
APP_NAME="$(jq -r '.application_name' <<<"${APP_JSON}")"
BUILD_NAME="$(jq -r '.build_name' <<<"${APP_JSON}")"
BUILD_INFO_REPO="$(gi_build_info_repo)"

gi_jf_api() {
  jf api --server-id "${SERVER_ID}" "$@"
}

gi_jf_post_json() {
  local method="$1" path="$2" body="$3"
  gi_jf_api -X "${method}" "${path}" \
    -H "Content-Type: application/json" \
    -d "${body}"
}

gi_preflight() {
  gi_log "Preflight JFrog CLI and APIs"
  jf --version >/dev/null
  jf apptrust --help >/dev/null
  gi_jf_api /access/api/v1/projects >/dev/null
  gi_jf_api /xray/api/v2/policies?projectKey="${PROJECT_KEY}" >/dev/null 2>&1 || true
  gi_jf_api /unifiedpolicy/api/v1/rule-templates >/dev/null 2>&1 \
    || gi_die "Unified Policy rule-templates API unavailable"
  gi_jf_api /evidence/api/v1/config/categories/ >/dev/null 2>&1 \
    || gi_die "Evidence categories API unavailable"
}

ensure_project() {
  if gi_jf_api "/access/api/v1/projects/${PROJECT_KEY}" >/dev/null 2>&1; then
    gi_log "Project ${PROJECT_KEY} exists"
    return 0
  fi
  [[ "${DRY_RUN}" == "1" ]] && { gi_log "DRY_RUN: would create project ${PROJECT_KEY}"; return 0; }
  gi_log "Creating project ${PROJECT_KEY}"
  gi_jf_post_json POST /access/api/v1/projects "{
      \"project_key\": \"${PROJECT_KEY}\",
      \"display_name\": \"${PROJECT_NAME}\",
      \"description\": \"Golden Image Management — approved base images\",
      \"admin_privileges\": {
        \"manage_members\": true,
        \"manage_resources\": true,
        \"manage_security_assets\": true,
        \"index_resources\": true,
        \"allow_ignore_rules\": true
      },
      \"storage_quota_bytes\": -1
    }"
}

ensure_docker_repo() {
  local key="$1" rclass="$2" extra="${3:-}"
  if gi_jf_api "/artifactory/api/repositories/${key}" >/dev/null 2>&1; then
    local pk
    pk="$(gi_jf_api "/artifactory/api/repositories/${key}" | jq -r '.projectKey // empty')"
    [[ -z "${pk}" || "${pk}" == "${PROJECT_KEY}" ]] \
      || gi_die "repo ${key} belongs to project ${pk}, expected ${PROJECT_KEY}"
    gi_log "Repo ${key} exists"
    return 0
  fi
  [[ "${DRY_RUN}" == "1" ]] && { gi_log "DRY_RUN: would create repo ${key}"; return 0; }
  gi_log "Creating repo ${key} (${rclass})"
  local payload
  if [[ "${rclass}" == "remote" ]]; then
    payload="$(jq -n \
      --arg key "${key}" \
      --arg proj "${PROJECT_KEY}" \
      '{
        key: $key,
        rclass: "remote",
        packageType: "docker",
        url: "https://registry-1.docker.io/",
        projectKey: $proj,
        externalDependenciesEnabled: true
      }')"
  else
    payload="$(jq -n \
      --arg key "${key}" \
      --arg proj "${PROJECT_KEY}" \
      --arg env "${extra}" \
      '{
        key: $key,
        rclass: "local",
        packageType: "docker",
        projectKey: $proj,
        environments: [$env]
      }')"
  fi
  gi_jf_post_json PUT "/artifactory/api/repositories/${key}" "${payload}"
}

assign_repo_environments() {
  local key="$1"
  shift
  local envs_json
  envs_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  [[ "${DRY_RUN}" == "1" ]] && return 0
  local cur
  cur="$(gi_jf_api "/artifactory/api/repositories/${key}")"
  local merged
  merged="$(echo "${cur}" | jq --argjson add "${envs_json}" \
    '.environments = ((.environments // []) + $add | unique)')"
  gi_jf_post_json POST "/artifactory/api/repositories/${key}" "${merged}" >/dev/null
  gi_log "Updated environments on ${key}"
}

ensure_lifecycle() {
  [[ "${DRY_RUN}" == "1" ]] && return 0
  gi_jf_post_json PATCH "/access/api/v2/lifecycle/?project_key=${PROJECT_KEY}" \
    "{\"project_key\":\"${PROJECT_KEY}\",\"promote_stages\":[\"DEV\",\"PROD\"]}"
  gi_log "Lifecycle promote_stages: DEV → PROD"
}

ensure_app() {
  if jf apptrust app-get "${APP_KEY}" --server-id "${SERVER_ID}" >/dev/null 2>&1; then
    gi_log "Application ${APP_KEY} exists"
    return 0
  fi
  [[ "${DRY_RUN}" == "1" ]] && { gi_log "DRY_RUN: would create app ${APP_KEY}"; return 0; }
  jf apptrust app-create "${APP_KEY}" \
    --project="${PROJECT_KEY}" \
    --application-name="${APP_NAME}" \
    --desc="Golden base image application (${APP_KEY})" \
    --maturity-level=production \
    --business-criticality=high \
    --server-id "${SERVER_ID}"
}

index_xray_repo() {
  local repo="$1"
  [[ "${DRY_RUN}" == "1" ]] && return 0
  local cur payload
  if ! cur="$(gi_jf_api "/xray/api/v1/repos_config/${repo}" 2>/dev/null)"; then
    cur="$(jq -n --arg r "${repo}" '{repo_name: $r, repo_config: {}}')"
  fi
  payload="$(echo "${cur}" | jq '.repo_config.retention_in_days = 90')"
  gi_jf_api -X PUT /xray/api/v1/repos_config \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  gi_log "Indexed Xray repo ${repo}"
}

index_build() {
  [[ "${DRY_RUN}" == "1" ]] && return 0
  local cur new
  cur="$(gi_jf_api "/xray/api/v1/binMgr/default/builds?projectKey=${PROJECT_KEY}")"
  new="$(echo "${cur}" | jq --arg b "${BUILD_NAME}" \
    'if (.indexed_builds // []) | index($b) then . else .indexed_builds = ((.indexed_builds // []) + [$b]) end')"
  gi_jf_api -X PUT "/xray/api/v1/binMgr/default/builds?projectKey=${PROJECT_KEY}" \
    -H "Content-Type: application/json" \
    -d "${new}" >/dev/null
  gi_log "Indexed build ${BUILD_NAME} for project ${PROJECT_KEY}"
}

ensure_xray_policy_watch() {
  local pol_name="golden-images-critical-cve-fail-build"
  local watch_name="golden-images-dev-watch"
  [[ "${DRY_RUN}" == "1" ]] && return 0

  if ! gi_jf_api "/xray/api/v2/policies/${pol_name}?projectKey=${PROJECT_KEY}" >/dev/null 2>&1; then
    gi_log "Creating Xray policy ${pol_name}"
    gi_jf_api -X POST "/xray/api/v2/policies?projectKey=${PROJECT_KEY}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${pol_name}\",
        \"description\": \"Fail builds with Critical CVEs (Golden Image CI)\",
        \"type\": \"security\",
        \"rules\": [{
          \"name\": \"critical-cve\",
          \"priority\": 1,
          \"criteria\": {
            \"min_severity\": \"Critical\"
          },
          \"actions\": {
            \"fail_build\": true,
            \"block_download\": { \"active\": false, \"unscanned\": false }
          }
        }]
      }" >/dev/null
  else
    gi_log "Xray policy ${pol_name} exists"
  fi

  if ! gi_jf_api "/xray/api/v2/watches/${watch_name}?projectKey=${PROJECT_KEY}" >/dev/null 2>&1; then
    gi_log "Creating Xray watch ${watch_name}"
    gi_jf_api -X POST "/xray/api/v2/watches?projectKey=${PROJECT_KEY}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${watch_name}\",
        \"description\": \"Golden DEV docker repo + project build-info\",
        \"active\": true,
        \"project_resources\": {
          \"resources\": [
            {\"type\": \"repository\", \"name\": \"${DEV_REPO}\"},
            {\"type\": \"build\", \"name\": \"${BUILD_NAME}\", \"build_repo\": \"${BUILD_INFO_REPO}\"}
          ]
        },
        \"policies\": [{\"name\": \"${pol_name}\", \"type\": \"security\"}]
      }" >/dev/null
  else
    gi_log "Xray watch ${watch_name} exists"
  fi
}

find_rule_template_id() {
  local hint="$1"
  gi_jf_api /unifiedpolicy/api/v1/rule-templates \
    | jq -r --arg h "${hint}" '
      (.items // .)[]
      | select((.description // "") | test($h; "i") or (.name // "") | test($h; "i"))
      | .id' | head -1
}

ensure_evidence_rule() {
  local rule_name="$1" predicate_uri="$2"
  [[ "${DRY_RUN}" == "1" ]] && return 0
  local rules rule_id template_id
  rules="$(gi_jf_api /unifiedpolicy/api/v1/rules)"
  rule_id="$(echo "${rules}" | jq -r --arg n "${rule_name}" '(.items // .)[] | select(.name==$n) | .id' | head -1)"
  template_id="$(find_rule_template_id "predicateType")"
  [[ -n "${template_id}" && "${template_id}" != "null" ]] \
    || template_id="1007"
  local body
  body="$(jq -n \
    --arg name "${rule_name}" \
    --arg tid "${template_id}" \
    --arg pred "${predicate_uri}" \
    '{
      name: $name,
      description: "Golden Image release gate evidence requirement",
      is_custom: true,
      template_id: $tid,
      parameters: [{name: "predicateType", value: $pred}]
    }')"
  if [[ -n "${rule_id}" && "${rule_id}" != "null" ]]; then
    gi_jf_api -X PUT "/unifiedpolicy/api/v1/rules/${rule_id}" \
      -H "Content-Type: application/json" \
      -d "${body}" >/dev/null
    gi_log "Updated rule ${rule_name}"
  else
    rule_id="$(gi_jf_api -X POST /unifiedpolicy/api/v1/rules \
      -H "Content-Type: application/json" \
      -d "${body}" | jq -r '.id')"
    gi_log "Created rule ${rule_name} (${rule_id})"
  fi
  printf '%s\n' "${rule_id}"
}

ensure_release_policy() {
  local policy_name="$1" rule_id="$2"
  [[ "${DRY_RUN}" == "1" ]] && return 0
  local pols pol_id
  pols="$(gi_jf_api "/unifiedpolicy/api/v1/policies?projectKey=${PROJECT_KEY}")"
  pol_id="$(echo "${pols}" | jq -r --arg n "${policy_name}" '(.items // .)[] | select(.name==$n) | .id' | head -1)"
  local body
  body="$(jq -n \
    --arg name "${policy_name}" \
    --arg rid "${rule_id}" \
    --arg proj "${PROJECT_KEY}" \
    '{
      name: $name,
      description: "PROD Release gate (Golden Image Management)",
      action: {type: "certify_to_gate", stage: {key: "PROD", gate: "release"}},
      enabled: true,
      mode: "block",
      rule_ids: [$rid],
      scope: {type: "project", project_keys: [$proj]}
    }')"
  if [[ -n "${pol_id}" && "${pol_id}" != "null" ]]; then
    gi_jf_api -X PUT "/unifiedpolicy/api/v1/policies/${pol_id}" \
      -H "Content-Type: application/json" \
      -d "${body}" >/dev/null
    gi_log "Updated policy ${policy_name}"
  else
    gi_jf_api -X POST /unifiedpolicy/api/v1/policies \
      -H "Content-Type: application/json" \
      -d "${body}" >/dev/null
    gi_log "Created policy ${policy_name}"
  fi
}

ensure_apptrust_release_policies() {
  local r1 r2 r3
  r1="$(ensure_evidence_rule "GI Golden Certification Required" "${GOLDEN_CERT}")"
  ensure_release_policy "GI PROD Release - Golden Certification" "${r1}"
  r2="$(ensure_evidence_rule "GI SLSA Provenance Required" "${SLSA_PRED}")"
  ensure_release_policy "GI PROD Release - SLSA Provenance" "${r2}"
  r3="$(ensure_evidence_rule "GI CycloneDX SBOM Required" "${SBOM_PRED}")"
  ensure_release_policy "GI PROD Release - CycloneDX SBOM" "${r3}"
  gi_log "Note: add AppTrust Critical CVE rule via UI or tenant-specific template if not present"
}

main() {
  gi_preflight
  ensure_project
  ensure_docker_repo "${UPSTREAM_REPO}" remote
  ensure_docker_repo "${DEV_REPO}" local DEV
  ensure_docker_repo "${RELEASE_REPO}" local PROD
  assign_repo_environments "${DEV_REPO}" DEV
  assign_repo_environments "${RELEASE_REPO}" PROD
  ensure_lifecycle
  ensure_app
  index_xray_repo "${DEV_REPO}"
  index_xray_repo "${RELEASE_REPO}"
  index_build
  ensure_xray_policy_watch
  ensure_apptrust_release_policies
  gi_log "Bootstrap complete for ${APP_KEY} in project ${PROJECT_KEY}"
}

main "$@"
