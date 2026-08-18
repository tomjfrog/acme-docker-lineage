#!/usr/bin/env bash
# Generate (or reuse) an Evidence signing keypair and upload the public key to tomjpd2.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd jf

if [[ -f "${KEY_FILE}" ]]; then
  log "Reusing existing key at ${KEY_FILE} (alias=${KEY_ALIAS})"
  # Ensure the public key is registered under KEY_ALIAS (anonymization may leave a stale alias).
  if ! jf api --server-id "${SERVER_ID}" /artifactory/api/security/keys/trusted 2>/dev/null \
      | jq -e --arg a "${KEY_ALIAS}" '[.keys[]?.alias] | index($a) != null' >/dev/null; then
    log "Trusted key alias ${KEY_ALIAS} missing — uploading ${KEYS_DIR}/evidence.pub"
    pub_json="$(jq -n --arg alias "${KEY_ALIAS}" --rawfile key "${KEYS_DIR}/evidence.pub" \
      '{alias:$alias, public_key:$key}')"
    printf '%s\n' "${pub_json}" > /tmp/acme-lineage-trusted-key.json
    jf api --server-id "${SERVER_ID}" -X POST \
      -H "Content-Type: application/json" \
      --input /tmp/acme-lineage-trusted-key.json \
      /artifactory/api/security/keys/trusted >/dev/null
    log "Uploaded trusted key alias=${KEY_ALIAS}"
  fi
  exit 0
fi

log "Generating evidence keypair alias=${KEY_ALIAS}"
jf evd gen-keys \
  --server-id "${SERVER_ID}" \
  --key-alias "${KEY_ALIAS}" \
  --key-file-path "${KEYS_DIR}" \
  --key-file-name evidence \
  --upload-public-key=true

chmod 600 "${KEY_FILE}"
log "Public key uploaded; private key at ${KEY_FILE}"
