#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

gi_log "validate-config and digest helpers"

assert_ok "catalog validates" "${GI_TEST_ROOT}/scripts/validate-config.sh" golden-alpine
assert_ok "golden-alpine resolves" gi_app_json golden-alpine

assert_ok "valid sha256 digest" gi_validate_sha256_digest sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
assert_fail "reject digest without prefix" gi_validate_sha256_digest 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
assert_fail "reject short digest" gi_validate_sha256_digest sha256:abc
assert_fail "reject uppercase hex" gi_validate_sha256_digest sha256:0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF

assert_ok "version 1.2.3" gi_validate_version_string 1.2.3
assert_fail "empty version" gi_validate_version_string ""
assert_fail "version with spaces" gi_validate_version_string "1.0 bad"

assert_ok "upstream path library/alpine" gi_assert_upstream_path golden-alpine library/alpine
assert_fail "wrong upstream path" gi_assert_upstream_path golden-alpine docker.io/alpine

test_summary
