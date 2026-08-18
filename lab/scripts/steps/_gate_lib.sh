#!/usr/bin/env bash
# Shared AppTrust gate helpers for GHA step wrappers.
# Logic mirrored from lab/scripts/03-apptrust-gate.sh (left intact).
# shellcheck shell=bash

PROJECT_KEY="${PROJECT_KEY:-dockerlineage}"
PROJECT_NAME="${PROJECT_NAME:-Docker Lineage}"
STAGE_KEY="${STAGE_KEY:-dockerlineage-PreProd}"
GATE="${GATE:-entry}"
POLICY_MODE="${POLICY_MODE:-block}"
APP_KEY="${APP_KEY:-payments-api}"
# AppTrust application version (may differ from Docker tag)
APP_VERSION="${APP_VERSION:-${APP_TAG}}"
PKG_VERSION="${PKG_VERSION:-${APP_TAG}}"
NEG_APP_KEY="${NEG_APP_KEY:-rogue-api}"
NEG_APP_VERSION="${NEG_APP_VERSION:-${NON_GOLDEN_TAG}}"
NEG_PKG_VERSION="${NEG_PKG_VERSION:-${NON_GOLDEN_TAG}}"

RULE_NAME="${RULE_NAME:-Docker Lineage - Derived-From Evidence Required}"
POLICY_NAME="${POLICY_NAME:-Docker Lineage - PreProd Entry Lineage Gate}"

detect_live_predicate() {
  local path types
  for path in \
      "${DOCKER_REPO}/${APP_NAME}/${APP_TAG}/list.manifest.json" \
      "${DOCKER_REPO}/${APP_NAME}/${APP_TAG}/manifest.json"; do
    types="$(jf evd get --subject-repo-path "${path}" --server-id "${SERVER_ID}" --format json 2>/dev/null \
      | jq -r '[.result.evidence[]?.predicateType // empty] | unique | .[]' 2>/dev/null || true)"
    if printf '%s\n' "${types}" | grep -q 'derived-from'; then
      printf '%s\n' "${types}" | grep 'derived-from' | head -1
      return 0
    fi
  done
  echo "${PREDICATE_TYPE_LINEAGE}"
}

PREDICATE_URI="${PREDICATE_URI:-$(detect_live_predicate)}"

jf_api() {
  jf api --server-id "${SERVER_ID}" "$@"
}

ensure_project() {
  if jf_api "/access/api/v1/projects/${PROJECT_KEY}" >/dev/null 2>&1; then
    log "Project ${PROJECT_KEY} exists"
    return 0
  fi
  log "Creating project ${PROJECT_KEY}"
  cat > /tmp/dl-project.json <<EOF
{
  "project_key": "${PROJECT_KEY}",
  "display_name": "${PROJECT_NAME}",
  "description": "Lab project for Docker golden-image lineage / AppTrust evidence gates",
  "admin_privileges": {
    "manage_members": true,
    "manage_resources": true,
    "manage_security_assets": true,
    "index_resources": true,
    "allow_ignore_rules": true
  },
  "storage_quota_bytes": -1
}
EOF
  jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-project.json /access/api/v1/projects
}

ensure_repo_in_project() {
  local status
  status="$(jf_api "/artifactory/api/repositories/${DOCKER_REPO}" 2>/dev/null | jq -r '.projectKey // empty')"
  if [[ "${status}" == "${PROJECT_KEY}" ]]; then
    log "Repo ${DOCKER_REPO} already in ${PROJECT_KEY}"
    return 0
  fi
  log "Assigning ${DOCKER_REPO} to ${PROJECT_KEY}"
  echo "{\"project_key\":\"${PROJECT_KEY}\"}" > /tmp/dl-move-repo.json
  jf_api -X PUT -H "Content-Type: application/json" --input /tmp/dl-move-repo.json \
    "/access/api/v1/projects/${PROJECT_KEY}/repositories/${DOCKER_REPO}" || \
  jf_api -X PUT -H "Content-Type: application/json" --input /tmp/dl-move-repo.json \
    "/access/api/v1/projects/${PROJECT_KEY}/repositories/${DOCKER_REPO}?force=true"
}

ensure_stage() {
  if jf_api "/access/api/v2/stages?project_key=${PROJECT_KEY}" 2>/dev/null \
      | jq -e --arg n "${STAGE_KEY}" 'map(select(.name==$n)) | length > 0' >/dev/null; then
    log "Stage ${STAGE_KEY} exists"
  else
    log "Creating stage ${STAGE_KEY}"
    cat > /tmp/dl-stage.json <<EOF
{
  "name": "${STAGE_KEY}",
  "scope": "project",
  "project_key": "${PROJECT_KEY}",
  "category": "promote"
}
EOF
    jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-stage.json /access/api/v2/stages || true
  fi

  local envs
  envs="$(jf_api "/artifactory/api/repositories/${DOCKER_REPO}" 2>/dev/null \
    | jq -c --arg s "${STAGE_KEY}" '(.environments // []) + ["DEV", $s] | unique')"
  cat > /tmp/dl-repo-env.json <<EOF
{
  "key": "${DOCKER_REPO}",
  "rclass": "local",
  "packageType": "docker",
  "environments": ${envs}
}
EOF
  jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-repo-env.json \
    "/artifactory/api/repositories/${DOCKER_REPO}" >/dev/null

  cat > /tmp/dl-lifecycle.json <<EOF
{
  "project_key": "${PROJECT_KEY}",
  "promote_stages": ["DEV", "${STAGE_KEY}"]
}
EOF
  jf_api -X PATCH -H "Content-Type: application/json" --input /tmp/dl-lifecycle.json \
    "/access/api/v2/lifecycle/?project_key=${PROJECT_KEY}" >/dev/null
  log "Lifecycle promote_stages: DEV → ${STAGE_KEY}"
}

ensure_rule() {
  local rules rule_id
  rules="$(jf_api /unifiedpolicy/api/v1/rules 2>/dev/null)"
  rule_id="$(echo "${rules}" | jq -r --arg n "${RULE_NAME}" '(.items // .)[] | select(.name==$n) | .id' | head -1)"
  if [[ -n "${rule_id}" && "${rule_id}" != "null" ]]; then
    log "Updating rule ${RULE_NAME} (${rule_id}) → ${PREDICATE_URI}"
    cat > /tmp/dl-rule.json <<EOF
{
  "name": "${RULE_NAME}",
  "description": "Blocks promotion unless Docker lineage derived-from Evidence is present.",
  "is_custom": true,
  "template_id": "1003",
  "parameters": [{"name": "predicateType", "value": "${PREDICATE_URI}"}]
}
EOF
    jf_api -X PUT -H "Content-Type: application/json" --input /tmp/dl-rule.json \
      "/unifiedpolicy/api/v1/rules/${rule_id}" >/dev/null
    echo "${rule_id}"
    return 0
  fi
  log "Creating rule ${RULE_NAME}"
  cat > /tmp/dl-rule.json <<EOF
{
  "name": "${RULE_NAME}",
  "description": "Blocks promotion unless Docker lineage derived-from Evidence is present.",
  "is_custom": true,
  "template_id": "1003",
  "parameters": [{"name": "predicateType", "value": "${PREDICATE_URI}"}]
}
EOF
  jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-rule.json \
    /unifiedpolicy/api/v1/rules | jq -r '.id'
}

ensure_policy() {
  local rule_id="$1"
  local pols pol_id
  pols="$(jf_api "/unifiedpolicy/api/v1/policies?projectKey=${PROJECT_KEY}" 2>/dev/null)"
  pol_id="$(echo "${pols}" | jq -r --arg n "${POLICY_NAME}" '(.items // .)[] | select(.name==$n) | .id' | head -1)"
  if [[ -n "${pol_id}" && "${pol_id}" != "null" ]]; then
    log "Policy ${POLICY_NAME} exists (${pol_id})"
    echo "${pol_id}"
    return 0
  fi
  log "Creating policy ${POLICY_NAME}"
  cat > /tmp/dl-policy.json <<EOF
{
  "name": "${POLICY_NAME}",
  "description": "Require lineage derived-from Evidence at ${STAGE_KEY} ${GATE} (${POLICY_MODE}).",
  "action": {
    "type": "certify_to_gate",
    "stage": { "key": "${STAGE_KEY}", "gate": "${GATE}" }
  },
  "enabled": true,
  "mode": "${POLICY_MODE}",
  "rule_ids": ["${rule_id}"],
  "scope": { "type": "project", "project_keys": ["${PROJECT_KEY}"] }
}
EOF
  jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-policy.json \
    /unifiedpolicy/api/v1/policies | jq -r '.id'
}

ensure_app() {
  local key="$1" name="$2"
  if jf apptrust app-get "${key}" --server-id "${SERVER_ID}" >/dev/null 2>&1; then
    log "App ${key} exists"
    return 0
  fi
  if jf apptrust app-create "${key}" \
      --project="${PROJECT_KEY}" \
      --application-name="${name}" \
      --desc="Lab app for Docker lineage gate" \
      --maturity-level=experimental \
      --business-criticality=medium \
      --server-id "${SERVER_ID}" 2>/dev/null; then
    log "Created app ${key}"
  else
    cat > /tmp/dl-app.json <<EOF
{
  "application_key": "${key}",
  "application_name": "${name}",
  "project_key": "${PROJECT_KEY}",
  "description": "Lab app for Docker lineage gate",
  "maturity_level": "experimental",
  "criticality": "medium"
}
EOF
    jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-app.json \
      /apptrust/api/v1/applications >/dev/null || true
    log "Ensured app ${key} via API"
  fi
}

ensure_version() {
  local app="$1" ver="$2" pkg="$3" pkg_ver="$4"
  if jf_api "/apptrust/api/v1/applications/${app}/versions?limit=50" 2>/dev/null \
      | jq -e --arg v "${ver}" '(.versions // .)[]? | select(.version==$v)' >/dev/null 2>&1; then
    log "Version ${app}@${ver} exists"
    return 0
  fi
  log "Creating version ${app}@${ver} from docker package ${pkg}:${pkg_ver}"
  cat > /tmp/dl-ver.json <<EOF
{
  "version": "${ver}",
  "sources": {
    "packages": [{
      "type": "docker",
      "name": "${pkg}",
      "version": "${pkg_ver}",
      "repository_key": "${DOCKER_REPO}"
    }]
  }
}
EOF
  jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-ver.json \
    "/apptrust/api/v1/applications/${app}/versions?async=false" >/dev/null
}

dry_run_promote() {
  local app="$1" ver="$2" expect="$3"
  cat > /tmp/dl-promote.json <<EOF
{
  "target_stage": "${STAGE_KEY}",
  "promotion_type": "dry_run"
}
EOF
  local body status decision
  body="$(jf_api -X POST -H "Content-Type: application/json" --input /tmp/dl-promote.json \
    "/apptrust/api/v1/applications/${app}/versions/${ver}/promote?async=false" 2>/dev/null || true)"
  status="$(echo "${body}" | jq -r '.status // empty')"
  decision="$(echo "${body}" | jq -r '.evaluations.entry_gate.decision // empty')"
  echo "${body}" | jq '{application: $app, version: $ver, status, decision: .evaluations.entry_gate.decision, explanation: .evaluations.entry_gate.explanation}' \
    --arg app "${app}" --arg ver "${ver}"
  if [[ "${expect}" == "pass" ]]; then
    [[ "${status}" == "success" && "${decision}" == "pass" ]] || die "Expected PASS for ${app}@${ver}, got status=${status} decision=${decision}"
    log "PASS as expected: ${app}@${ver}"
  else
    [[ "${status}" == "failed" || "${decision}" == "fail" ]] || die "Expected FAIL for ${app}@${ver}, got status=${status} decision=${decision}"
    log "FAIL as expected: ${app}@${ver}"
  fi
}
