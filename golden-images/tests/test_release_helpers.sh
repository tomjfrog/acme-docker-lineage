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

test_summary
