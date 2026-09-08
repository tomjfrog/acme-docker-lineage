#!/usr/bin/env bash
# One-shot generator for the lab-only Golden Image CA.
# Commit acme-lab-root-ca.crt only. Never copy the private key into the image.
set -euo pipefail
CERTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="${CERTS_DIR}/private"
CRT="${CERTS_DIR}/acme-lab-root-ca.crt"
KEY="${PRIVATE_DIR}/acme-lab-root-ca.key"

mkdir -p "${PRIVATE_DIR}"
chmod 700 "${PRIVATE_DIR}"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${KEY}" \
  -out "${CRT}" \
  -days 3650 \
  -sha256 \
  -subj "/C=US/O=Acme Docker Lineage Lab/CN=Acme Lab Root CA (NOT FOR PRODUCTION)"

chmod 600 "${KEY}"
echo "Wrote ${CRT}"
echo "Wrote ${KEY} (gitignored; do not commit or COPY into the image)"
openssl x509 -noout -subject -dates -fingerprint -sha256 -in "${CRT}"
