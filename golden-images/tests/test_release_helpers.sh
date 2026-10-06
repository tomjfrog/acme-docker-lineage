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

INDEX='sha256:0b737e9d1849f9ecf580361e7daf5f55e6e43c51aad0fcf029dc86eb10605d26'
AMD64='sha256:0b7d90ffa8bcdf49c0ec4ece70a6813e3d7d26299d3d8cc9ca4730b46e13982b'
BUILD_INFO_INDEX_FIXTURE="$(jq -n --arg hex "0b737e9d1849f9ecf580361e7daf5f55e6e43c51aad0fcf029dc86eb10605d26" '{
  buildInfo: { modules: [{ id: "golden-alpine:v1.0.4", artifacts: [{ name: "list.manifest.json", sha256: $hex }] }] }
}')"
BUILD_INFO_PLATFORM_FIXTURE="$(jq -n --arg hex "0b7d90ffa8bcdf49c0ec4ece70a6813e3d7d26299d3d8cc9ca4730b46e13982b" '{
  buildInfo: { modules: [{ artifacts: [{ name: "manifest.json", sha256: $hex }] }] }
}')"
BUILD_INFO_PATH_FIXTURE="$(jq -n --arg path "golden-alpine/sha256:0b7d90ffa8bcdf49c0ec4ece70a6813e3d7d26299d3d8cc9ca4730b46e13982b/manifest.json" '{
  buildInfo: { modules: [{ artifacts: [{ path: $path }] }] }
}')"

assert_ok "build-info list.manifest bare hex matches index" gi_build_info_references_digest "${BUILD_INFO_INDEX_FIXTURE}" "${INDEX}"
assert_fail "build-info index digest miss (platform-only build-info)" gi_build_info_references_digest "${BUILD_INFO_PLATFORM_FIXTURE}" "${INDEX}"

assert_ok "build-info platform digest hit (bare hex)" gi_build_info_references_digest "${BUILD_INFO_PLATFORM_FIXTURE}" "${AMD64}"
assert_ok "build-info platform digest hit (embedded path)" gi_build_info_references_digest "${BUILD_INFO_PATH_FIXTURE}" "${AMD64}"
assert_ok "build-info any digest (platform)" test "$(gi_build_info_references_any_digest "${BUILD_INFO_PLATFORM_FIXTURE}" "${INDEX}" "${AMD64}")" = "${AMD64}"

test_summary
