# Local iteration with `act`

These workflows are **`workflow_dispatch` only**. `act` defaults to a **`push`** event, so bare `act` will not run them.

## Correct event

```bash
act workflow_dispatch -W .github/workflows/01-publish-golden.yml --secret-file .github/act/secrets
```

## Secrets file

```bash
cp .github/act/secrets.example .github/act/secrets
# edit .github/act/secrets — never commit it
```

Required for live JPD calls:

| Key | Purpose |
|---|---|
| `JF_URL` | e.g. `https://tomjpd2.jfrog.io` |
| `JF_ACCESS_TOKEN` | Platform access token (`act` cannot use GitHub OIDC) |
| `EVIDENCE_SIGNING_KEY` | PEM (or base64 PEM) matching trusted alias `acme-lineage-lab` |

Optional (ignored under act when token is set): `OIDC_PROVIDER_NAME`, `OIDC_AUDIENCE`.

## Docker socket (image builds)

Two different paths matter on Rancher Desktop / macOS:

| Setting | Purpose |
|---|---|
| `DOCKER_HOST` | How **`act` on the Mac** reaches the daemon (`~/.rd/docker.sock`) |
| `--container-daemon-socket` | What **`act` bind-mounts into job containers** for `docker build` / push |

If `DOCKER_HOST` is unset, you often get `failed to connect … /var/run/docker.sock`.

If `DOCKER_HOST` points at `~/.rd/docker.sock` and you leave the default mount, `act` tries to bind-mount that **host** path and fails with `mkdir …/docker.sock: operation not supported`. Tell it to mount the socket that exists **inside** the Rancher Desktop VM instead: `unix:///var/run/docker.sock`.

Do **not** also pass `--container-options "-v …/docker.sock:/var/run/docker.sock"` — that causes `Duplicate mount point: /var/run/docker.sock`.

Rancher Desktop:

```bash
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"

act workflow_dispatch -W .github/workflows/01-publish-golden.yml \
  --secret-file .github/act/secrets \
  --container-daemon-socket unix:///var/run/docker.sock \
  --input run_id=localdemo1
```

Docker Desktop (socket usually already at `/var/run/docker.sock`; `DOCKER_HOST` / `--container-daemon-socket` often optional):

```bash
act workflow_dispatch -W .github/workflows/01-publish-golden.yml \
  --secret-file .github/act/secrets \
  --input run_id=localdemo1
```

On Apple Silicon, if containers misbehave, add `--container-architecture linux/amd64`.

## Demo order (same as GitHub Actions UI)

Use a shared `run_id` so beats chain:

```bash
RID=localdemo1
SECRETS=.github/act/secrets
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"
ACT_DOCKER=(--container-daemon-socket unix:///var/run/docker.sock)

act workflow_dispatch -W .github/workflows/00-setup-evidence-keys.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/01-publish-golden.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/02-publish-bar-from-golden.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/03-publish-fizz-multihop.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/04-rename-without-ci.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/05-publish-non-golden.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/06-detect-lineage.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/07-apptrust-gate-bootstrap.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID" --input app_version=2.0.0 --input neg_app_version=1.0.0
act workflow_dispatch -W .github/workflows/08-apptrust-gate-verify.yml --secret-file "$SECRETS" "${ACT_DOCKER[@]}" --input run_id="$RID" --input app_version=2.0.0 --input neg_app_version=1.0.0
```

On GitHub.com, leave `JF_ACCESS_TOKEN` unset to use OIDC (`OIDC_PROVIDER_NAME` / `OIDC_AUDIENCE` + `vars.JF_URL`).

## Inputs via JSON payload (alternative)

```bash
cat > /tmp/dispatch.json <<'EOF'
{ "inputs": { "run_id": "localdemo1" } }
EOF
act workflow_dispatch -W .github/workflows/01-publish-golden.yml \
  --secret-file .github/act/secrets \
  -e /tmp/dispatch.json
```
