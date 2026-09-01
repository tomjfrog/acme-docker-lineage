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
| `EVIDENCE_SIGNING_KEY` | PEM **or** single-line base64 PEM matching trusted alias `acme-lineage-lab` |

`act` secret files are plain `KEY=VALUE` — they do **not** expand shell (`$(…)`). Putting a command string literally causes `Restore Evidence signing key` → `base64: invalid input`.

Prefer base64 (one line, no newlines). After `lab/scripts/00-gen-keys.sh` (or if `lab/keys/evidence.key` already exists):

```bash
# rewrite just the EVIDENCE_SIGNING_KEY line (macOS/BSD sed)
b64="$(base64 < lab/keys/evidence.key | tr -d '\n')"
sed -i '' "s|^EVIDENCE_SIGNING_KEY=.*|EVIDENCE_SIGNING_KEY=${b64}|" .github/act/secrets
```

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
  -P ubuntu-latest=catthehacker/ubuntu:act-22.04 \
  --input run_id=localdemo1
```

Docker Desktop (socket usually already at `/var/run/docker.sock`; `DOCKER_HOST` / `--container-daemon-socket` often optional):

```bash
act workflow_dispatch -W .github/workflows/01-publish-golden.yml \
  --secret-file .github/act/secrets \
  --input run_id=localdemo1
```

On Apple Silicon, if containers misbehave, add `--container-architecture linux/amd64`.

## Runner image (TLS to JFrog)

`act`’s default job image is `node:16-buster-slim`. Its CA bundle is too old to trust current `*.jfrog.io` certificates, which shows up as:

`tls: failed to verify certificate: x509: certificate signed by unknown authority`

Map `ubuntu-latest` to a current act image (pull once):

```bash
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
```

## Artifacts under `act`

`actions/upload-artifact@v4` needs `ACTIONS_RUNTIME_TOKEN` (GitHub-hosted only). Without it the publish steps can succeed on the JPD while `act` still reports **Job failed**.

Workflows skip upload when `env.ACT` is set (`if: ${{ !env.ACT }}`). Local outputs remain under `lab/out/<run_id>/`.

## Idempotency note

Re-running **01 Publish golden** against the same image tag/digest attaches **another** golden Evidence record each time (harmless for demos). Tracked as `TODO(idempotency)` in `lab/scripts/steps/publish-golden.sh`.

## JFrog CLI version

`setup-lab` pins **JFrog CLI 2.120.0** via `jfrog/setup-jfrog-cli` (the action’s default 2.91.0 lacks `jf api`, which AppTrust/Access bootstrap needs). Local `jf -v` should be similarly recent if you run `lab/scripts/03-apptrust-gate.sh` outside Actions/`act`.

## Deactivated JPD (silent failures)

A paused/deactivated SaaS instance answers **every** request with a `302` to `https://landing.jfrog.com/reactivate-server/<instance>`, which serves the JFrog landing page as `200 text/html`. Nothing errors cleanly, so you instead see:

- `jf api` returning HTML with `Http Status: 200`, so callers report `Project … exists` when it does not
- `jq` choking with `parse error: Invalid numeric literal at line 1, column 10` (that's `<!DOCTYPE html>`)
- `jf docker login` printing `Login Succeeded` because `/v2/` answered 200 without an auth challenge

Confirm with `curl -sI "${JF_URL}/artifactory/api/system/version" | grep -i location`, reactivate the instance, then re-run. `setup-lab` now runs `jf rt ping` and fails immediately with the reactivate link.

## Demo order (same as GitHub Actions UI)

Use a shared `run_id` so beats chain:

```bash
RID=localdemo1
SECRETS=.github/act/secrets
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"
ACT_OPTS=(
  --container-daemon-socket unix:///var/run/docker.sock
  -P ubuntu-latest=catthehacker/ubuntu:act-22.04
)

act workflow_dispatch -W .github/workflows/00-setup-evidence-keys.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/01-publish-golden.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}"
act workflow_dispatch -W .github/workflows/02-publish-payments-api-from-golden.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}"
act workflow_dispatch -W .github/workflows/03-publish-salestax-api-multihop.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}"
act workflow_dispatch -W .github/workflows/04-rename-without-ci.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/05-publish-non-golden.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/06-detect-lineage.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID"
act workflow_dispatch -W .github/workflows/07-apptrust-gate-bootstrap.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID" --input app_version=2.0.1 --input neg_app_version=1.0.1
act workflow_dispatch -W .github/workflows/08-apptrust-gate-verify.yml --secret-file "$SECRETS" "${ACT_OPTS[@]}" --input run_id="$RID" --input app_version=2.0.1 --input neg_app_version=1.0.1
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

## Related documentation

Customer-facing JFrog product links (Evidence, Build Info, AppTrust, Docker) are in the repo root [README](../../README.md) and in [FINDINGS.md — Documentation](../../FINDINGS.md#documentation-customer-leave-behind).

For this `act` / GitHub Actions path specifically:

- [GitHub: OIDC Authentication](https://docs.jfrog.com/integrations/docs/github-actions-oidc-authentication) — use on GitHub.com; `act` cannot use OIDC, so set `JF_ACCESS_TOKEN` instead
- [OpenID Connect Integration](https://docs.jfrog.com/administration/docs/openid-connect-integration) — platform-side OIDC provider
- [jfrog/setup-jfrog-cli](https://github.com/jfrog/setup-jfrog-cli) — action used by `setup-lab` (pin CLI ≥ 2.120.0 for `jf api`)
- [Create Evidence using the JFrog CLI](https://docs.jfrog.com/governance/docs/create-evidence-using-the-jfrog-cli) — `jf evd create` on publish workflows
- [Use Docker with JFrog CLI](https://docs.jfrog.com/artifactory/docs/jf-docker) — `jf docker push` / login against the JPD
