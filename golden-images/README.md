# Golden Image Management (AppTrust)

Isolated control plane for **approved base images**: project `golden-images`, one AppTrust Application per base family (starting with `golden-alpine`), DEV → PROD lifecycle, and a **Trusted Release** on PROD after Release-gate evidence and Xray posture checks.

This is separate from the lineage lab under [`lab/`](../lab/) and workflows `00`–`08`. Child application images that must consume a parent Golden **Trusted Release** are the next phase.

## Prerequisites

- JFrog Platform with AppTrust, Xray/SBOM, and Evidence Collection (see [AppTrust prerequisites](https://docs.jfrog.com/governance/docs/apptrust-prerequisites.md)).
- GitHub Actions OIDC to Artifactory (`OIDC_PROVIDER_NAME`, `vars.JF_URL`, `vars.JF_DOCKER_REGISTRY`).
- Repository secret `EVIDENCE_SIGNING_KEY` (same pattern as workflow `01-publish-golden.yml`).
- OIDC identity with **platform** project-create and project admin privileges for bootstrap.

## Catalog

[`catalog.json`](catalog.json) defines project keys, repositories, evidence predicate URIs, and applications. [`platform-inventory.json`](platform-inventory.json) lists every platform object bootstrap creates (names, types, and whether to use **JFrog MCP** vs **`jf api` / CLI**). Add JDK/Node by extending `applications[]` and inventory, plus a matching `golden-images/<family>/` build context — no script forks.

Validate:

```bash
./golden-images/scripts/validate-config.sh golden-alpine
```

## Bootstrap (once per environment)

GitHub Actions: **09 Golden Images bootstrap** (`.github/workflows/09-golden-images-bootstrap.yml`).

Local (requires configured `jf` and admin token/OIDC):

```bash
export SERVER_ID=tomjpd2
./golden-images/scripts/bootstrap.sh golden-alpine
```

Creates or reconciles:

- Project `golden-images` and repos `golden-images-upstream-docker-remote`, `golden-images-dev-docker-local`, `golden-images-release-docker-local`
- Lifecycle promote path **`DEV`** only in `promote_stages` (global **`PROD`** is category **release**, not promote — Trusted Release via `version-release` after Release gate)
- AppTrust application `golden-alpine`
- Xray Critical **fail_build** policy + watches `golden-images-dev-build-watch` (build-info) and `golden-images-dev-repo-watch` (DEV docker repo) — see inventory
- PROD Release policies for Golden certification, SLSA provenance, CycloneDX SBOM v1.6 (tenant rule templates discovered at bootstrap)

Re-run bootstrap to verify idempotency: each step checks whether the resource already exists (GET/list) and **skips** create/update when nothing is missing. Incompatible drift (e.g. repo owned by another project) still fails loudly.

**Agents:** before adding platform provisioning, read **`jfrog`**, **`jfrog-xray-policies-watches`**, **`jfrog-lifecycle-stages`**, and **`jfrog-apptrust-gates`** skills (and lab `jf_api` patterns in `lab/scripts/03-apptrust-gate.sh`). Run `jf … --help` for any subcommand you script; use watch templates in the Xray skill, not ad-hoc JSON.

## Release a Golden Alpine version

Workflow **10 Release Golden Alpine** (`.github/workflows/10-release-golden-alpine.yml`).

Required dispatch inputs:

| Input | Meaning |
|---|---|
| `app_version` | Immutable image tag and AppTrust version (e.g. `1.0.0`) |
| `upstream_tag` | Official `library/alpine` tag |
| `upstream_digest` | `sha256:<64 hex>` for that tag on Docker Hub |

Flow:

1. **build-and-scan** — digest-pinned build through the upstream remote, multi-arch push to DEV, Build Info publish, `jf build-scan --fail=true` (Xray watch), GitHub provenance attestation (ingested by `setup-jfrog-cli` post-step).
2. **certify-and-release** — AppVersion from **Build Info only**, pre-cert PROD promote dry-run (expects block), Golden certification evidence, `jf apptrust version-release` with copy to PROD, digest verification on `golden-images-release-docker-local`.

## Tests

```bash
./golden-images/tests/run.sh
```

## Operator notes

- **Xray vs AppTrust:** a green `build-scan` means the CI watch policy passed; PROD Release still evaluates lifecycle policies independently.
- **Multi-arch:** the OCI **index** digest is the release identity; do not substitute a single-platform manifest digest.
- **No overwrite:** release uses `--overwrite-strategy=disabled`; pick a new `app_version` for each publish.
