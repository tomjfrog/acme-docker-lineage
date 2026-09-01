#!/usr/bin/env bash
# Detect whether candidate images are derived from the golden base via:
#   1) layer DiffID prefix matching (forensic / rename-safe / multi-hop root)
#   2) Evidence lookup (explicit provenance when present)
#   3) Evidence parent-chain walk (multi-hop: salestax-api → payments-api → golden-base)
#   4) Build Info presence (supporting signal)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd docker
require_cmd jf
require_cmd jq

RUN_STAMP="${1:-}"
if [[ -z "${RUN_STAMP}" ]]; then
  [[ -f "${OUT_DIR}/latest-run.txt" ]] || die "No run stamp; pass a run id or run 01-build-push.sh first"
  RUN_STAMP="$(cat "${OUT_DIR}/latest-run.txt")"
fi
RUN_DIR="${OUT_DIR}/${RUN_STAMP}"
[[ -d "${RUN_DIR}" ]] || die "Run directory not found: ${RUN_DIR}"

RESULTS="${RUN_DIR}/lineage-results.json"
REPORT="${RUN_DIR}/lineage-report.md"

GOLDEN_DIGEST="$(cat "${RUN_DIR}/golden.digest.txt")"
APP_DIGEST_FILE="${RUN_DIR}/app.digest.txt"
APP_DIGEST=""
[[ -f "${APP_DIGEST_FILE}" ]] && APP_DIGEST="$(cat "${APP_DIGEST_FILE}")"

is_prefix() {
  # $1 = golden layers file, $2 = candidate layers file
  local golden="$1" candidate="$2"
  local gcount ccount
  gcount="$(wc -l < "${golden}" | tr -d ' ')"
  ccount="$(wc -l < "${candidate}" | tr -d ' ')"
  if (( gcount == 0 || ccount < gcount )); then
    return 1
  fi
  local i=1
  while (( i <= gcount )); do
    local g c
    g="$(sed -n "${i}p" "${golden}")"
    c="$(sed -n "${i}p" "${candidate}")"
    [[ "${g}" == "${c}" ]] || return 1
    i=$((i + 1))
  done
  return 0
}

# Fetch Evidence JSON for a package tag; writes to $3.
fetch_evidence_json() {
  local name="$1" version="$2" out_file="$3"
  local subject
  for subject in \
      "${DOCKER_REPO}/${name}/${version}/list.manifest.json" \
      "${DOCKER_REPO}/${name}/${version}/manifest.json"; do
    if jf evd get \
        --server-id "${SERVER_ID}" \
        --subject-repo-path "${subject}" \
        --include-predicate \
        --format json 2>/dev/null \
        | tee "${out_file}" \
        | jq -e '
            (.result.evidence // .evidence // (if type=="array" then . else [] end))
            | length > 0
          ' >/dev/null 2>&1; then
      return 0
    fi
  done
  printf '%s\n' '{"result":{"evidence":[]}}' > "${out_file}"
  return 1
}

# Prefer newest lineage predicate; optionally match predicate.image_digest.
pick_predicate() {
  local file="$1"
  local prefer_digest="${2:-}"
  jq -c --arg prefer "${prefer_digest}" '
    (.result.evidence // .evidence // (if type=="array" then . else [] end))
    | map(select(.predicate.base_image_digest != null))
    | if ($prefer != "" and (map(select(.predicate.image_digest == $prefer)) | length) > 0)
      then map(select(.predicate.image_digest == $prefer))
      else . end
    | sort_by(.createdAt) | reverse | .[0].predicate // empty
  ' "${file}" 2>/dev/null || true
}

check_evidence_package() {
  local name="$1" version="$2"
  local out="${RUN_DIR}/evidence-${name}-${version}.json"
  if fetch_evidence_json "${name}" "${version}" "${out}"; then
    echo "found"
    return 0
  fi
  echo "missing"
  return 1
}

evidence_base_digest() {
  local file="$1"
  local prefer_digest="${2:-}"
  local pred
  pred="$(pick_predicate "${file}" "${prefer_digest}")"
  [[ -n "${pred}" && "${pred}" != "null" ]] || { echo ""; return 0; }
  printf '%s' "${pred}" | jq -r '.base_image_digest // empty'
}

evidence_base_package() {
  local file="$1"
  local prefer_digest="${2:-}"
  local pred
  pred="$(pick_predicate "${file}" "${prefer_digest}")"
  [[ -n "${pred}" && "${pred}" != "null" ]] || { echo -e "\t"; return 0; }
  printf '%s' "${pred}" | jq -r '[(.base_package_name // empty), (.base_package_version // empty)] | @tsv'
}

# Walk Evidence parent digests until golden, known dead-end, or max hops.
# Echoes: true|path  or  false|path
walk_evidence_to_golden() {
  local start_name="$1" start_ver="$2"
  local max_hops="${3:-5}"
  local chain=()
  local cur_name="${start_name}" cur_ver="${start_ver}"
  local hop=0
  local prefer_digest=""

  case "${start_name}:${start_ver}" in
    "${APP_NAME}:${APP_TAG}")
      [[ -f "${RUN_DIR}/app.digest.txt" ]] && prefer_digest="$(cat "${RUN_DIR}/app.digest.txt")"
      ;;
    "${SALESTAX_NAME}:${SALESTAX_TAG}")
      [[ -f "${RUN_DIR}/salestax.digest.txt" ]] && prefer_digest="$(cat "${RUN_DIR}/salestax.digest.txt")"
      ;;
  esac

  while (( hop < max_hops )); do
    local ev_file="${RUN_DIR}/evidence-walk-${cur_name}-${cur_ver}.json"
    if ! fetch_evidence_json "${cur_name}" "${cur_ver}" "${ev_file}"; then
      chain+=("${cur_name}:${cur_ver}(no-evidence)")
      echo "false|${chain[*]}"
      return 1
    fi
    chain+=("${cur_name}:${cur_ver}")

    local base_digest
    base_digest="$(evidence_base_digest "${ev_file}" "${prefer_digest}")"
    if [[ -z "${base_digest}" ]]; then
      echo "false|${chain[*]}→(no-base-digest)"
      return 1
    fi

    if [[ "${base_digest}" == "${GOLDEN_DIGEST}" ]]; then
      chain+=("golden@${GOLDEN_DIGEST}")
      echo "true|${chain[*]}"
      return 0
    fi

    local pkg_tsv next_name="" next_ver=""
    pkg_tsv="$(evidence_base_package "${ev_file}" "${prefer_digest}")"
    next_name="$(printf '%s' "${pkg_tsv}" | cut -f1)"
    next_ver="$(printf '%s' "${pkg_tsv}" | cut -f2)"

    if [[ -z "${next_name}" || -z "${next_ver}" ]]; then
      if [[ -n "${APP_DIGEST}" && "${base_digest}" == "${APP_DIGEST}" ]]; then
        next_name="${APP_NAME}"
        next_ver="${APP_TAG}"
      else
        chain+=("unresolved@${base_digest}")
        echo "false|${chain[*]}"
        return 1
      fi
    fi

    prefer_digest=""
    if [[ "${next_name}:${next_ver}" == "${APP_NAME}:${APP_TAG}" && -f "${RUN_DIR}/app.digest.txt" ]]; then
      prefer_digest="$(cat "${RUN_DIR}/app.digest.txt")"
    fi

    cur_name="${next_name}"
    cur_ver="${next_ver}"
    hop=$((hop + 1))
  done

  echo "false|${chain[*]}→(max-hops)"
  return 1
}

check_build_info() {
  local build_name="$1"
  if jf rt curl -X GET "/api/build/${build_name}" --server-id "${SERVER_ID}" 2>/dev/null \
      | jq -e '.buildsNumbers or .builds or .uri' >/dev/null 2>&1; then
    echo "found"
  else
    echo "missing"
  fi
}

GOLDEN_LAYERS="${RUN_DIR}/golden.layers.txt"
[[ -f "${GOLDEN_LAYERS}" ]] || die "missing ${GOLDEN_LAYERS}"

# case_id|layers|pkg|tag|build|expect_layers|walk_evidence
declare -a CASES=(
  "app|${RUN_DIR}/app.layers.txt|${APP_NAME}|${APP_TAG}|acme-lineage-app|expect_match|walk"
  "salestax|${RUN_DIR}/salestax.layers.txt|${SALESTAX_NAME}|${SALESTAX_TAG}|acme-lineage-salestax|expect_match|walk"
  "app_renamed|${RUN_DIR}/app-renamed.layers.txt|${APP_RENAMED_NAME}|${APP_RENAMED_TAG}|none|expect_match|skip"
  "non_golden|${RUN_DIR}/non-golden.layers.txt|${NON_GOLDEN_NAME}|${NON_GOLDEN_TAG}|acme-lineage-nongolden|expect_no_match|skip"
)

json_cases='[]'

{
  echo "# Lineage detection report"
  echo
  echo "Run: \`${RUN_STAMP}\`"
  echo "Golden (Foo): \`$(cat "${RUN_DIR}/golden.ref.txt")\`"
  echo "Golden digest: \`${GOLDEN_DIGEST}\`"
  echo "Image chain: golden-base=\`${GOLDEN_NAME}\` → payments-api=\`${APP_NAME}\` → salestax-api=\`${SALESTAX_NAME}\`"
  echo
  echo "| Case | Layer prefix of golden? | Evidence on package | Evidence walk → golden? | Build Info | Verdict |"
  echo "|---|---|---|---|---|---|"
} > "${REPORT}"

pass_count=0
fail_count=0

for entry in "${CASES[@]}"; do
  IFS='|' read -r case_id layers_file pkg_name pkg_ver build_name expect walk_mode <<< "${entry}"

  if [[ ! -f "${layers_file}" ]]; then
    die "missing layers file for ${case_id}: ${layers_file} (re-run 01-build-push.sh)"
  fi

  layer_match="false"
  if is_prefix "${GOLDEN_LAYERS}" "${layers_file}"; then
    layer_match="true"
  fi

  evidence_status="skipped"
  if evidence_status="$(check_evidence_package "${pkg_name}" "${pkg_ver}")"; then
    :
  else
    evidence_status="missing"
  fi

  walk_status="n/a"
  walk_path=""
  if [[ "${walk_mode}" == "walk" ]]; then
    walk_raw="$(walk_evidence_to_golden "${pkg_name}" "${pkg_ver}" || true)"
    walk_root="$(printf '%s' "${walk_raw}" | cut -d'|' -f1)"
    walk_path="$(printf '%s' "${walk_raw}" | cut -d'|' -f2-)"
    if [[ "${walk_root}" == "true" ]]; then
      walk_status="true"
    else
      walk_status="false"
    fi
  fi

  build_status="n/a"
  if [[ "${build_name}" != "none" ]]; then
    build_status="$(check_build_info "${build_name}")"
  fi

  verdict="UNKNOWN"
  ok="false"
  if [[ "${expect}" == "expect_match" ]]; then
    if [[ "${layer_match}" == "true" ]]; then
      if [[ "${walk_mode}" == "walk" && "${walk_status}" == "true" ]]; then
        verdict="ROOT_IS_GOLDEN (layers + Evidence walk)"
      elif [[ "${walk_mode}" == "walk" && "${walk_status}" == "false" ]]; then
        verdict="ROOT_IS_GOLDEN (layers); Evidence walk incomplete (${walk_path})"
      else
        verdict="DERIVED_FROM_GOLDEN (layer prefix)"
      fi
      ok="true"
    else
      verdict="FAIL: expected golden derivation via layers"
      ok="false"
    fi
    if [[ "${case_id}" == "salestax" && "${walk_status}" != "true" ]]; then
      verdict="FAIL: salestax-api Evidence walk did not reach golden (${walk_path})"
      ok="false"
    fi
  else
    if [[ "${layer_match}" == "false" ]]; then
      verdict="NOT_DERIVED_FROM_GOLDEN"
      ok="true"
    else
      verdict="FAIL: unexpected golden layer prefix"
      ok="false"
    fi
  fi

  if [[ "${ok}" == "true" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi

  echo "| ${case_id} | ${layer_match} | ${evidence_status} | ${walk_status}${walk_path:+ (${walk_path})} | ${build_status} | ${verdict} |" >> "${REPORT}"

  json_cases="$(jq -n \
    --argjson acc "${json_cases}" \
    --arg id "${case_id}" \
    --argjson layer_match "${layer_match}" \
    --arg evidence "${evidence_status}" \
    --arg walk "${walk_status}" \
    --arg walk_path "${walk_path}" \
    --arg build "${build_status}" \
    --arg expect "${expect}" \
    --arg verdict "${verdict}" \
    --argjson ok "${ok}" \
    '$acc + [{
      case: $id,
      layer_prefix_match: $layer_match,
      evidence: $evidence,
      evidence_walk_reaches_golden: $walk,
      evidence_walk_path: $walk_path,
      build_info: $build,
      expect: $expect,
      verdict: $verdict,
      ok: $ok
    }]'
  )"
done

jq -n \
  --arg run "${RUN_STAMP}" \
  --arg golden_ref "$(cat "${RUN_DIR}/golden.ref.txt")" \
  --arg golden_digest "${GOLDEN_DIGEST}" \
  --arg chain "golden-base=${GOLDEN_NAME} → payments-api=${APP_NAME} → salestax-api=${SALESTAX_NAME}" \
  --argjson cases "${json_cases}" \
  --argjson pass "${pass_count}" \
  --argjson fail "${fail_count}" \
  '{
    run: $run,
    image_chain: $chain,
    golden: {ref: $golden_ref, digest: $golden_digest},
    cases: $cases,
    summary: {pass: $pass, fail: $fail}
  }' > "${RESULTS}"

{
  echo
  echo "## Summary"
  echo
  echo "- Pass: ${pass_count}"
  echo "- Fail: ${fail_count}"
  echo
  echo "JSON: \`${RESULTS}\`"
  echo
  echo "## Multi-hop notes"
  echo
  echo "- **Tier 2 (layers):** golden DiffID prefix on salestax-api proves root is golden even when \`FROM\` was payments-api."
  echo "- **Tier 1 (Evidence):** salestax-api predicate names only payments-api; walk salestax-api → payments-api → golden-base is required unless \`root_golden_digest\` is recorded."
} >> "${REPORT}"

log "Report → ${REPORT}"
cat "${REPORT}"

if (( fail_count > 0 )); then
  die "Lineage detection had ${fail_count} failing case(s)"
fi
log "All lineage expectations met."
