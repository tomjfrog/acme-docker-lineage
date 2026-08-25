# Acme Docker lineage lab

Local experiment against `https://tomjpd2.jfrog.io` validating golden-image lineage after rename **and** multi-hop derivation (`golden-base` → `payments-api` → `fizz-service`).

## Prerequisites

- Rancher Desktop (Docker). Local scripts set `DOCKER_HOST` to Rancher’s socket when not in CI.
- JFrog CLI configured with server id `tomjpd2` (default).
- `jq` on `PATH`.

## Quick start (local scripts — unchanged)

```bash
./lab/scripts/00-gen-keys.sh      # once — uploads Evidence public key
./lab/scripts/01-build-push.sh    # build/push golden, payments-api, Fizz, renamed, non-golden
./lab/scripts/02-detect-lineage.sh
./lab/scripts/03-apptrust-gate.sh # Tier 3: project/stage + AppTrust evidence gate dry-runs
```

Artifacts land in `lab/out/<timestamp>/` (gitignored). Keys in `lab/keys/` (gitignored).

Per-beat scripts under `lab/scripts/steps/` power GitHub Actions; they do **not** replace the scripts above.

## GitHub Actions (workflow_dispatch demos)

Each beat is a separate **`workflow_dispatch`** workflow so you can narrate it for customers:

| Order | Workflow | Proves |
|---|---|---|
| 00 | `00-setup-evidence-keys.yml` | Signing key / `acme-lineage-lab` |
| 01 | `01-publish-golden.yml` | Golden + Build Info + Evidence |
| 02 | `02-publish-payments-api-from-golden.yml` | payments-api FROM golden + lineage Evidence |
| 03 | `03-publish-fizz-multihop.yml` | Multi-hop Fizz; immediate-parent Evidence |
| 04 | `04-rename-without-ci.yml` | Rename without Evidence (Tier 2 still works) |
| 05 | `05-publish-non-golden.yml` | Negative control |
| 06 | `06-detect-lineage.yml` | Detector report (layers + Evidence walk) |
| 07 | `07-apptrust-gate-bootstrap.yml` | Project / PreProd / policy / AppTrust versions |
| 08 | `08-apptrust-gate-verify.yml` | Dry-run promote pass + fail |

Share the same `run_id` input across 01–06 when chaining. Auth: **OIDC** on GitHub.com (`OIDC_PROVIDER_NAME`, `OIDC_AUDIENCE`, `vars.JF_URL`); **`JF_ACCESS_TOKEN`** for local `act` (see [`.github/act/README.md`](../.github/act/README.md)).

```bash
# act requires the workflow_dispatch event name (default is push)
act workflow_dispatch -W .github/workflows/01-publish-golden.yml --secret-file .github/act/secrets
```

### Tier 3 (AppTrust gate)

Project `dockerlineage`, stage `dockerlineage-PreProd` **entry** gate in **block** mode requiring derived-from lineage Evidence. Dry-run: payments-api **passes**; rogue-api **fails**.

## Images

Lab image names:

| Image | Purpose |
|---|---|
| `golden-base:1.0.0` | Approved golden base |
| `payments-api:2.0.0` | Direct descendant: built `FROM` golden + Evidence (`base` = golden) |
| `fizz-service:0.1.0` | Multi-hop: built `FROM` payments-api; Evidence names **only** payments-api |
| `billing-service:9.9.9` | Same layers as payments-api, renamed tag (no Evidence) |
| `rogue-api:1.0.0` | Built on debian (not golden) |

All push to `tomjpd2.jfrog.io/lineage-docker-local/…`.

## What the detector proves

1. **Layer DiffID prefix** of golden on payments-api, Fizz, and renamed → root is golden (Tier 2).
2. **Evidence walk** fizz-service → payments-api → golden-base → root is golden even when Fizz’s predicate omits the golden digest (Tier 1 multi-hop).
3. Non-golden has neither layer prefix nor a walk to golden.
