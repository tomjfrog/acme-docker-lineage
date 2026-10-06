#!/usr/bin/env bash
# Static checks: golden-images scripts follow lab jf api conventions (path last, --input for bodies).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

gi_log "jf api conventions"

static_ok=0
while IFS= read -r -d '' f; do
  if grep -E 'jf api .* -d |gi_jf_api -X "[A-Z]+" /|gi_jf_api -X [A-Z]+ /' "${f}" \
      | grep -v 'gi_jf_request_json' >/dev/null 2>&1; then
    echo "unexpected jf api pattern in ${f} (use gi_jf_request_json; path last; --input not -d):" >&2
    grep -nE 'jf api .* -d |gi_jf_api -X "[A-Z]+" /|gi_jf_api -X [A-Z]+ /' "${f}" >&2 || true
    static_ok=1
  fi
done < <(find "${GI_ROOT}/scripts" -name '*.sh' -print0)

assert_ok "no inline -d or path-before-headers in scripts" test "${static_ok}" -eq 0

test_summary
