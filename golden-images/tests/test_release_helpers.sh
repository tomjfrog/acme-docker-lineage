#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

gi_log "release helper contracts"

assert_ok "build-info repo name" test "$(gi_build_info_repo)" = "golden-images-build-info"

# Digest equality helper (used by release.sh)
gi_digest_equal() {
  local a="$1" b="$2"
  [[ "${a}" == "${b}" ]]
}

assert_ok "digest match" gi_digest_equal sha256:abc sha256:abc
assert_fail "digest mismatch" gi_digest_equal sha256:abc sha256:def

INDEX='sha256:aaecbdceedba51d9c28916dd87313979761e26f20b43828f5d41a785ce80572b'
AMD64='sha256:d9b4a2a3a0321f8a5c261f7429c830167cd024bf63fb17cf447eb9c238d07676'
BUILD_INFO_FIXTURE="$(jq -n --arg amd "${AMD64}" '{
  buildInfo: { modules: [{ artifacts: [{ sha256: $amd }] }] }
}')"

assert_fail "build-info index digest miss (platform-only build-info)" gi_build_info_references_digest "${BUILD_INFO_FIXTURE}" "${INDEX}"

assert_ok "build-info platform digest hit" gi_build_info_references_digest "${BUILD_INFO_FIXTURE}" "${AMD64}"
assert_ok "build-info any digest (platform)" test "$(gi_build_info_references_any_digest "${BUILD_INFO_FIXTURE}" "${INDEX}" "${AMD64}")" = "${AMD64}"

test_summary
