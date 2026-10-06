#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob
for t in "${DIR}"/test_*.sh; do
  echo "--- $(basename "${t}") ---"
  bash "${t}"
done
