#!/usr/bin/env bash
set -euo pipefail

GI_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GI_REPO_ROOT="$(cd "${GI_TEST_ROOT}/.." && pwd)"
# shellcheck source=../scripts/common.sh
source "${GI_TEST_ROOT}/scripts/common.sh"

TESTS_RUN=0
TESTS_FAILED=0

assert_ok() {
  local desc="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@"; then
    printf '  ok  %s\n' "${desc}"
  else
    printf ' FAIL %s\n' "${desc}" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_fail() {
  local desc="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! "$@" 2>/dev/null; then
    printf '  ok  %s (expected failure)\n' "${desc}"
  else
    printf ' FAIL %s (expected failure, got success)\n' "${desc}" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

test_summary() {
  printf '\n%d test(s), %d failure(s)\n' "${TESTS_RUN}" "${TESTS_FAILED}"
  [[ "${TESTS_FAILED}" -eq 0 ]]
}
