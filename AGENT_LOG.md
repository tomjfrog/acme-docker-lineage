# Agent log

Dated notes for later agents. Newest entry first. Product/lineage facts belong in `FINDINGS.md`; this file is session context, remotes, and “do not re-learn this.” Follow the 2026-08-30 16:39 conventions when migrating remaining GitHub Actions workflows. **Do not** `jf rt set-props` in native GHA or lab scripts (2026-09-01).

---

## 2026-09-01 15:34 EDT — Native 03 + rename fizz-service → salestax-api

Native catalog job: [`.github/workflows/03-publish-salestax-api-multihop.yml`](.github/workflows/03-publish-salestax-api-multihop.yml). Same auth/attest/Build Info pattern as 02. Parent vet is **payments-api:2.0.0** (not golden). Evidence predicate stays `derived_from_golden: false` / `immediate_parent_only: true`. No `setup-lab`, no `jf rt set-props`.

**Rename:** catalog image is `salestax-api:0.1.0` (was `fizz-service`). Scripts use `SALESTAX_*`. Build Info `acme-lineage-salestax`. Detector artifacts `salestax.*.txt`. Local script remains [`lab/scripts/steps/publish-salestax-api.sh`](lab/scripts/steps/publish-salestax-api.sh) (single-arch); GHA does not invoke it.

**Catalog leftover:** `lineage-docker-local/fizz-service` may still exist on `tomjpd2` until overwritten/deleted. After 03 runs, AQL hits should be `salestax-api/0.1.0` per-arch `manifest.json`.

**Next native migrate:** 04 rename (copy in catalog, no Evidence). setup-lab still wraps 00, 04–08.

---

## 2026-09-01 15:15 EDT — Inherited OCI labels live proof; drop `set-props` (this thread)

Human closed after validating Docker `LABEL` inheritance in Artifactory and removing CI-set item properties. Product facts stay in `FINDINGS.md`; this entry is what later agents must not re-learn.

### What we did

1. Confirmed the repo has **no** cleanup/teardown scripts or workflows for lab fixtures (images, builds, Evidence, projects). Historical `uhg-*` deletion in FINDINGS was one-off/manual.
2. Validated the human’s assumption: **workflows 00–08 and `02-detect-lineage.sh` do not assert inherited labels.** Detector is DiffID prefix + Evidence walk + Build Info. Dockerfiles were already shaped so `com.acme.image.golden=true` inherits (children override `title`/`role`/`expected_base` only). Prior AQL proof (2026-08-30 16:44) was manual, not a lab step.
3. Added a **golden-only** test marker `LABEL` so inheritance is unambiguous vs the existing golden key. First commit used the misspelling `com.acme.iamge.foo=bar`. Human fixed it on GitHub.com to **`com.acme.image.foo=bar`**. Current Dockerfile key is `com.acme.image.foo`.
4. Human published **01** then **02** on `tomjpd2` / `lineage-docker-local`. Agent confirmed properties via AQL + `?properties` (not the tag-folder UI).
5. Removed **all** `jf rt set-props` from native workflows **01–02**, `lab/scripts/01-build-push.sh`, `lab/scripts/steps/publish-*.sh`, and unused `jf_rt`/`set_props` in `lib.sh`. Detector/gates/Evidence never read those keys. FINDINGS no longer describes the lab as setting `golden.image` / `com.acme.base.digest`; still warns that `set-props` **does not cascade** and must not be used for descendant inventory.

### What we validated (`tomjpd2`)

**Where `docker.label.*` lives (operators keep missing this):** Artifactory copies OCI `config.Labels` onto **per-arch** `manifest.json` under `golden-base/sha256:<platform>/`, not onto `golden-base/1.0.0/list.manifest.json` (OCI index) and not onto attestation `unknown/unknown` manifests. The Artifacts tree tag folder `1.0.0` shows the index + four digest children; two are real images, two are Buildx attestations (often share blob `sha256__44136fa3…` = empty JSON). Packages view does not show digest folders. Property search for `foo` on an attestation `manifest.json` correctly returns 0.

**Golden `1.0.0` after 01 run `33544135625` (checkout `ec1f9b7`, then human typo-fix + republish as needed):** linux/amd64 and linux/arm64 `manifest.json` had `docker.label.com.acme.iamge.foo=bar` while the key was still misspelled. After the GitHub typo fix, search **`docker.label.com.acme.image.foo=bar`**. Also present: `docker.label.com.acme.image.golden=true`, role, title. Index had only `jf rt set-props` overlay (`golden.image=true`, …) — those writes are now gone from CI; leftovers may remain on old tag folders until overwritten/deleted.

**Payments-api `2.0.0` after 02 run `33545340313` (18:44Z, after the new golden):** inheritance **yes** on both platform manifests.

| Property | payments-api value | Source |
|---|---|---|
| `docker.label.com.acme.iamge.foo` (then `…image.foo` after typo fix) | `bar` | Inherited (not in payments Dockerfile) |
| `docker.label.com.acme.image.golden` | `true` | Inherited |
| `docker.label.com.acme.image.role` | `app` | Child override |
| `docker.label.org.opencontainers.image.title` | `acme-app-from-golden` | Child override |
| `docker.label.com.acme.image.expected_base` | `golden` | Child-only |

UI path that actually has labels (amd64 example from that run): `lineage-docker-local/payments-api/sha256:108e9b0253e323bee9da22e5f82c2e04ea3e699836a77fcd2755eed3bc00ef88/manifest.json`. Skip `2.0.0/list.manifest.json` and attestation sha256 folders.

AQL: `items.find({"repo":"lineage-docker-local","name":"manifest.json","@docker.label.com.acme.image.foo":"bar"})`. After 03/04, salestax-api + billing-service should hit the same way if rebuilt FROM the labeled golden/payments; 05 rogue-api must miss. Catalog path `fizz-service` is leftover until 03 republishes as `salestax-api`.

### Git this thread (do not reverse remotes rules)

| Commit | Where | What |
|---|---|---|
| `147e647` | both | golden-only `iamge.foo` label |
| `495965f` | GitHub.com first | typo → `com.acme.image.foo` |
| `f21044e` | `origin/main` cherry-pick of that fix | same patch, different parent |
| `33f0b02` | both | remove `set-props`; FINDINGS wording |
| `9d91adf` | `external` `main` (`public` merge) | refresh GitHub.com |

Untracked locally and **not** committed: `AGENT_LOG.md`, `output-examples/`, `raw-logs.txt`.

### Do not

- Re-add `jf rt set-props` when migrating 03–08 to native GHA.
- Tell operators to read labels from `list.manifest.json`, `docker manifest inspect` of the tag, or `@golden.image`.
- Treat leftover tag-folder properties from old publishes as the lineage signal.

---

## 2026-08-30 16:46 CDT — Internal vs public Git remotes (this thread)

Human has **two remotes** and wanted GitHub.com customer-facing without SA specs, slide-agent prompts, or “Customer talking points.” Implemented as a **divergent `public` branch**, not a history rewrite. Do not re-plan this; do not `git push` `main` to `external`.

### Remotes (authoritative)

| Remote | URL | What lives there |
|---|---|---|
| `origin` | `git@github.jfrog.info:tomj/acme-docker-image.git` | Full tree. Colleague collaboration. |
| `external` | `git@github.com:tomjfrog/acme-docker-lineage.git` | Stripped tree. `public` is pushed as **`main`**. |

Local **`main` tracks `origin/main`**. Colleague work happens on `main`. Branch **`public` is GitHub.com only**.

### Human decisions (do not reverse without asking)

- **Forward-only** on GitHub.com: a new commit deletes files. Older commits (`d50eaf2`, `8961f84`, and anything before the strip) **still contain** `SPEC.md`, `DECK_SPEC.md`, `PROBLEM_STATEMENT.md`, and the PPTX. `git filter-repo` + force-push of `external` was explicitly **not** chosen.
- Public tree also drops **`PROBLEM_STATEMENT.md`**, not only the three originally named files.
- Keep on public: lab, workflows, `FINDINGS.md`, a public-worded `README.md`.

### What `public` must not contain

`git rm` on **`public` only** (never on `main` / `origin`):

- `SPEC.md` — customer ask (names, ESRO, registry hosts)
- `DECK_SPEC.md` — slide prompt (“Feed this file to a subagent”, `jfrog-slide-design-system`)
- `PROBLEM_STATEMENT.md`
- `Image_governance_spec.pptx`
- `~$Image_governance_spec.pptx` — Office lockfile; `.gitignore` has `~$*.pptx` on both trees

On `public` after rm: drop SPEC/DECK/PROBLEM links from `README.md`; drop FINDINGS “Customer talking points” (later moved into `DECK_SPEC.md` on **internal** `main`); drop SPEC alias comments in `lab/README.md` and `lab/scripts/lib.sh`; rewrite workflow first-line `# Customer talking point:` comments to plain descriptions.

Internal `README.md` has the remotes / refresh reminder. **Public README must not** mention `origin`/`external` or link `DECK_SPEC.md` / `SPEC.md` / `PROBLEM_STATEMENT.md`.

### Git rules (break these and you leak internals or delete colleague files)

1. **Never merge `public` into `main`.**
2. **Never push `main` to `external`.** `git push` with no remote while on `main` goes to `origin` only (tracking is set).
3. **Never push the strip commit to `origin`.** Internal keeps specs and the deck.
4. Refresh GitHub.com after `main` moves:

```bash
git checkout public
git merge main
# re-git rm SPEC.md DECK_SPEC.md PROBLEM_STATEMENT.md Image_governance_spec.pptx if merge restored them
# re-apply public README / FINDINGS wording if merge brought internal voice back
git push external public:main
git checkout main
```

First strip commit: `434c9d3`. Internal remotes note: `2126815`. Later public refreshes are merge commits (`fbcc4c0`, `e744b40`, `5ac3409`, …).

### Why this exists

Same working copy, two audiences. Internal = SA working notes + deck generation. Public = lab + findings leave-behind. Histories diverged on purpose after they had been identical (`8961f84` on both remotes).

---

## 2026-08-30 16:44 CDT — Recap: can we search descendants by OCI `LABEL`? (this thread)

Human asked whether **Stored Packages GraphQL** could search Docker packages by a **specific OCI `LABEL`** (Dockerfile `LABEL` / `config.Labels`), then expanded to AQL/REST, inheritance to golden descendants, a customer recommendation, a live lab proof, and docs. Work landed in `FINDINGS.md` (and talking points in `DECK_SPEC.md`). Do not re-research GraphQL for this; the answer is no.

### Product answers (keep these)

| Question | Answer |
|---|---|
| Search OCI `LABEL` via OneModel `storedPackages`? | **No.** No `hasLabelsWith`. `hasTagsWith` / `hasQualifiersWith` are Metadata tags/qualifiers, not `config.Labels`. Docs: [Stored Packages GraphQL](https://docs.jfrog.com/integrations/docs/stored-packages-onemodel-graphql). |
| Search OCI `LABEL` in Artifactory at all? | **Yes.** On push, Artifactory copies labels onto **that image’s** `manifest.json` as properties `docker.label.<oci-key>`. Docs: [Docker Labels](https://docs.jfrog.com/artifactory/docs/additional-docker-information), [KB `docker.label.` prefix](https://jfrog.com/help/r/artifactory-retrieving-docker-labels-using-manifest-json-in-artifactory-via-rest-api-call/artifactory-retrieving-docker-labels-using-manifest.json-in-artifactory-via-rest-api-call). |
| Do parent labels cascade in Artifactory? | **Artifactory does not walk `FROM`.** It indexes whatever is already in **this** image’s config. |
| Do parent labels appear on children? | **Yes, via the Docker builder.** Un-overridden `LABEL`s inherit on `FROM` (including multi-hop). Last `LABEL` with the same key wins. `COPY --from` / final `FROM scratch` does **not** inherit labels. |
| Search descendants of golden **today**? | **AQL** (preferred) or `GET /artifactory/api/search/prop` on `docker.label.com.acme.image.golden` (lab key). Restrict `name: manifest.json`. |
| Layer squash vs this search? | Classic `--squash` **does not** strip labels (they live in **config**). Squash **does** break Tier 2 DiffID prefix. Scratch/`COPY --from` and `export`/`import` **do** drop labels. |
| Lab `jf rt set-props` `golden.image=true`? | **Does not cascade.** Historical lab overlay; publish jobs **no longer** call `set-props`. Do not search `@golden.image` for lineage inventory. |

Canonical write-up + curl/wget: `FINDINGS.md` → [OCI golden-marker labels — searchable today](FINDINGS.md#oci-golden-marker-labels--searchable-today) (query starts ~line 58). Docs table also links AQL execution.

### Lab proof (`tomjpd2` / `lineage-docker-local`)

AQL `@docker.label.com.acme.image.golden=true` on `manifest.json`:

| Path | Role | Hit? |
|---|---|---|
| `golden-base/1.0.0` | Sets the label | Yes |
| `payments-api/2.0.0` | `FROM` golden | Yes (inherited; child overrode `title`/`role`) |
| `salestax-api/0.1.0` | Multi-hop `FROM` payments-api | Yes (never set `com.acme.image.golden` in its Dockerfile). Historical catalog path was `fizz-service/0.1.0`. |
| `billing-service/9.9.9` | Rename of payments-api | Yes |
| `rogue-api/1.0.0` | debian | **No** |

REST `GET /artifactory/api/search/prop?…docker.label.com.acme.image.golden=true` also returned four hits; AQL is what to recommend.

Golden Dockerfile marker: `com.acme.image.golden=true` (plus `com.acme.image.role`, `org.opencontainers.image.title`). App Dockerfiles must **not** redefine the marker key.

Customer framing: inventory of images whose **published config still carries the golden marker**, not signed provenance. Evidence / DiffIDs remain the audit/forensic path.

### Docs / deck / git

- Talking points **moved out of** `FINDINGS.md` **into** `DECK_SPEC.md` (speaker bank, not extra slides; CVS verbal-only). Public GitHub tree **strips** `DECK_SPEC.md` / `SPEC.md` / `PROBLEM_STATEMENT.md`.
- Remotes: `origin` = `github.jfrog.info:tomj/acme-docker-image.git` (full `main`). `external` = `github.com:tomjfrog/acme-docker-lineage.git` (stripped `public` pushed as `main`). Never merge `public` → `main`. Refresh: `git checkout public && git merge main`, `git rm` restored spec/deck if needed, keep public README (no internal remotes/DECK links), `git push external public:main`, `git checkout main`.
- Commits on this thread (internal `main`): `0af0528` AQL findings + talking points to deck; `200c999` curl/wget AQL POST examples. Public merges: `fbcc4c0`, `e744b40`.

### How to POST the AQL

`POST /artifactory/api/search/aql`, `Content-Type: text/plain`, body = raw AQL (not JSON). Bearer or `-u`. wget: `--method=POST --body-file=golden-label.aql`. Details and examples are in `FINDINGS.md`.

### Related later the same day (other entries below)

A **different** session on 2026-08-30 covered `docker manifest inspect` vs config labels vs multi-arch indexes, and native GHA for **01-publish-golden**. Do not mix that operator model with this AQL recommendation: labels are in **config** / Artifactory `docker.label.*` on **per-arch** `manifest.json`, not on the index.

---

## 2026-08-30 16:41 CDT — OCI inspect vs manifest vs labels (golden-base:1.0.1)

Session with the human (started 2026-08-26): debugging why `docker manifest inspect` failed for a locally built golden, then how multi-arch inspect and OCI `LABEL`s actually work. Capture this so later agents do not mix up **local image store**, **registry index**, **platform manifest**, and **config**. Product facts for lineage still live in `FINDINGS.md`; this entry is the operator mental model.

### What happened

1. `docker image ls` showed `tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.1` (ID `148327c5ab17`, distinct from catalog `golden-base:1.0.0` at `5c78daa04e2a`).
2. `docker manifest inspect` on that ref returned `no such manifest`.
3. Human confirmed the image was **built locally and not pushed**. After push, the tag resolved to a **manifest list** (multi-arch / OCI index), not a single image manifest.
4. Human expected Dockerfile `LABEL`s (`com.acme.image.golden`, etc.) in manifest JSON. They are not there. Human then identified the mix-up: **image inspect vs manifest inspect**.

Lab catalog tag remains **`golden-base:1.0.0`** (workflows, Evidence, AQL proofs). **`1.0.1` was a local/multi-arch experiment**, not a replacement for the 1.0.0 catalog entry unless someone later promotes it.

Saved sample of a verbose list inspect: `output-examples/multi-arch-oci-manifest-inspect.json` (`docker manifest inspect …:1.0.1 -v`). It shows `linux/arm64` (real image: config digest + layer digests) and `unknown/unknown` (Buildx/SLSA **attestation** manifest with `application/vnd.in-toto+json`, predicate `https://slsa.dev/provenance/v1`). Skip `unknown/unknown` when comparing layer chains.

Native **01 Publish golden** now pushes `platforms: linux/amd64,linux/arm64`, so CI golden is also an index. Custom `jf evd create` already falls back `list.manifest.json` then `manifest.json` (see the 16:39 entry).

### Mental model (do not conflate)

Same tag name, **different blobs**:

| Command / object | What it is | Where labels live | Where layer digests live |
|---|---|---|---|
| `docker image ls` / local `docker image inspect` | Rancher/Docker **local store**. A `registry/repo:tag` name is only a local tag until push. | `Config.Labels` | Local history / DiffIDs, not the registry index |
| `docker manifest inspect <tag>` (no digest) | **Registry** Distribution API. After multi-arch push: **index / manifest list**. | No | No (only pointers to per-arch manifests) |
| Platform image manifest (`<tag>@sha256:…` of `linux/amd64` or `linux/arm64`) | OCI image manifest: `config` + `layers[]` | No | **Yes** — use this for lineage DiffID / layer-prefix |
| Image **config** blob | `application/vnd.oci.image.config.v1+json` | **Yes** — Dockerfile `LABEL` → `config.Labels` | DiffIDs in `rootfs` |
| Index/manifest **annotations** | Optional OCI annotations on index, descriptors, or manifest | Different from labels | n/a |
| Artifactory `docker.label.*` | Properties Artifactory copies from **that image’s config** onto **that** `manifest.json` at push | Searchable overlay, not an OCI field | n/a |

`docker manifest inspect` **never** reads the local store. Untagged-in-registry, not-yet-pushed, or 404-as-unauthenticated from Artifactory all print `no such manifest`.

Dockerfile `LABEL` ≠ manifest field. Docker docs: **labels** describe the image (config); **annotations** describe index/manifest/descriptors.

### Commands that actually answer the question

Index (platforms + digests):

```bash
docker buildx imagetools inspect tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.1
docker manifest inspect -v tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.1
```

One architecture’s **image** manifest (layers):

```bash
docker buildx imagetools inspect "${IMG}@sha256:<platform-digest>" --raw
docker manifest inspect "${IMG}@sha256:<platform-digest>"
```

Config / labels from registry (`.Image` is config, not the index):

```bash
docker buildx imagetools inspect --format '{{json (index .Image "linux/arm64")}}' "$IMG"
```

Labels on a **local** image:

```bash
docker image inspect --format '{{json .Config.Labels}}' "$IMG"
```

In Artifactory, the **tag** folder holds `list.manifest.json`; each arch is its own `manifest.json` under a sha256 path. `docker.label.*` is on the **per-arch** `manifest.json`, not the list. AQL in `FINDINGS.md` already filters `name: manifest.json` and `@docker.label.com.acme.image.golden`.

### Implications for this lab / future agents

- Lineage layer-prefix: compare **platform** manifests (same OS/arch), not the index digest and not attestation manifests.
- Multi-arch CI: tag digest from `docker/build-push-action` is the **index**. Evidence/attest subject is that index digest; layer forensics still need each arch.
- Do not tell customers “read labels from `docker manifest inspect`.” Point them at config, `imagetools` `.Image`, or Artifactory `docker.label.*` / AQL.
- Do not treat a local `tomjpd2.jfrog.io/…` tag as published. Catalog jobs pull **pushed** stable tags (`1.0.0`, `2.0.0`, …).

---

## 2026-08-30 16:39 CDT — Native GHA for Publish Golden; catalog-native jobs

Reference implementation: `.github/workflows/01-publish-golden.yml`. Lab scripts under `lab/scripts/` stay for local runs; do not delete them.

### What we changed

- Rewrote **01 Publish golden** as named native Actions steps. It no longer calls `./lab/scripts/steps/publish-golden.sh` or `./.github/actions/setup-lab`.
- Dropped `workflow_dispatch` `run_id` inputs and GitHub artifact chaining (`lineage-run-<id>` download/upload). Jobs are **independent catalog jobs**: the next workflow pulls **stable tags** from Artifactory, not a prior GHA run.
- JFrog Build Info **build number** is `${{ github.run_number }}-<stable-tag>` (example: `1-1.0.0`). Image **tags stay fixed** (`golden-base:1.0.0`, `payments-api:2.0.0`, etc.).
- Platform URL and Docker registry host come from **repository variables** with **no YAML fallbacks**: `vars.JF_URL`, `vars.JF_DOCKER_REGISTRY`.
- Auth: **OIDC on GitHub.com**, **access token only under `act`**. Split on `env.ACT`, not on whether a token is set.
- Removed `oidc-audience` / `OIDC_AUDIENCE`. This JPD OIDC integration has no audience.
- **Do not** put `JF_ACCESS_TOKEN` in **job-level** `env:`. A dummy GitHub secret caused `jfrog/setup-jfrog-cli` to configure `--access-token` instead of completing OIDC. Docker/OIDC login still worked, and the inline `jf evd create` succeeded, but **Post Setup JFrog CLI (OIDC)** Evidence Collection failed with `authentication failed`. Token is scoped to the `if: ${{ env.ACT }}` setup step only. GitHub repository secret `JF_ACCESS_TOKEN` should **not exist**.
- Verified on GitHub.com after the token-scope fix: image push, Build Info, custom golden Evidence, and post-job SLSA Evidence collection succeeded.

### Conventions for remaining workflows (02–08, optionally 00)

Treat **01** as the pattern. Migrate one dispatchable workflow at a time. Keep scripts until that workflow is native.

**Do**

1. Native steps, not repo scripts. Official actions: `jfrog/setup-jfrog-cli@v4` (CLI 2.120.0), `docker/setup-qemu-action@v4`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`, `actions/attest-build-provenance@v3`. Short inline `run:` only for CLI with no first-party action (`jf evd create`, `jf rt build-docker-create` / `build-publish`). Do **not** `jf rt set-props`.
2. Permissions: `id-token: write` and `contents: read` always. Add `attestations: write` if the job uses `actions/attest-build-provenance`.
3. Job env: `JF_URL: ${{ vars.JF_URL }}`, `JF_DOCKER_REGISTRY: ${{ vars.JF_DOCKER_REGISTRY }}`, plus image constants (repo, name, stable tag, build name, predicate URI, `KEY_ALIAS=acme-lineage-lab`). No `|| 'https://…'` defaults.
4. Auth steps (copy from 01):
   - OIDC: `if: ${{ !env.ACT }}`, `id: setup-jfrog-cli`, `oidc-provider-name: ${{ secrets.OIDC_PROVIDER_NAME }}` only. No `oidc-audience`. No `JF_ACCESS_TOKEN` in that step’s env.
   - Token: `if: ${{ env.ACT }}`, `JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}` **only on this step**.
   - Docker login OIDC: `docker/login-action` with `registry: ${{ env.JF_DOCKER_REGISTRY }}`, `oidc-user` / `oidc-token`.
   - Docker login act: `jf docker login "${JF_DOCKER_REGISTRY}"`.
5. Images: multi-arch `platforms: linux/amd64,linux/arm64` unless a talking point needs a single manifest. Tag `${JF_DOCKER_REGISTRY}/${DOCKER_REPO}/${NAME}:${STABLE_TAG}`.
6. Provenance: after push, `actions/attest-build-provenance@v3` with `subject-name: oci://${JF_DOCKER_REGISTRY}/${DOCKER_REPO}/${NAME}` and `subject-digest` from build-push. `setup-jfrog-cli` post-job ingests the Sigstore bundle. Do not put a dummy access token anywhere that post step can see.
7. Build Info after docker/build-push-action: write `{"image":"<ref>@<digest>"}`, then `jf rt build-docker-create <local-repo> --image-file … --build-name … --build-number "${BUILD_NUM}"`, `build-collect-env` (best-effort), `build-publish`. `BUILD_NUM` = `${GITHUB_RUN_NUMBER}-${STABLE_TAG}`.
8. Custom Evidence: write PEM to `$RUNNER_TEMP/evidence.key` from `secrets.EVIDENCE_SIGNING_KEY` (raw PEM if it contains `BEGIN`, else base64-decode). `jf evd create` with `--key-alias acme-lineage-lab`. Package-scoped first; fallback `list.manifest.json` then `manifest.json` for multi-arch.
9. Catalog, not GHA artifacts, as the chain. 02 must `docker pull` `golden-base:1.0.0` (scripts already do this if `golden.digest.txt` is missing). Do not `download-artifact` a previous workflow. Optional upload-artifact is this-run logs only, never a required input to the next job.
10. Secrets/vars on GitHub.com: variables `JF_URL`, `JF_DOCKER_REGISTRY`; secrets `OIDC_PROVIDER_NAME`, `EVIDENCE_SIGNING_KEY` (raw PEM). Not used: `OIDC_AUDIENCE`, `JF_ACCESS_TOKEN` (act-only, `.github/act/secrets`).
11. Evidence key match: trusted alias `acme-lineage-lab`. Fingerprint the platform public key vs a local private key; the trusted-keys API may return empty `fingerprint` fields.

**Do not**

- Invoke `lab/scripts/steps/*.sh` from a workflow you are migrating to native GHA.
- Pass `run_id` between workflows or key artifacts on `github.run_id` for chaining.
- Put `JF_ACCESS_TOKEN` in job `env:`.
- Pass `oidc-audience` unless the JPD integration actually has one.
- Hard-code the JPD hostname in workflow YAML.
- Use unique CI image tags for this lab; overwrite stable tags in `lineage-docker-local`.
- Merge branch `public` into `main`. Remotes: `origin` = internal full tree; `external` = GitHub.com. Refresh public with `git checkout public && git merge main`, strip spec/deck files if they return, `git push external public:main`.

### Dual-use of setup-lab until a workflow is native

`.github/actions/setup-lab` still wraps 00 and 04–08 (01–03 are native). It already takes required `jf_url` + `docker_registry`, sets `BUILD_NUM` from run_number + optional `image_tag`, and splits OIDC vs token on `env.ACT`. Remaining native migrations should **stop calling setup-lab** (same as 01–03).

Caveat: 04–08 still set job-level `JF_ACCESS_TOKEN`. Safe while GitHub has **no** that secret. If anyone re-adds a dummy GitHub token, those jobs and any future attest post-step will regress. When converting a workflow, drop that job env line.

### Still script-backed (migrate next, same pattern)

| Workflow | Local script | Stable tag | Notes |
|---|---|---|---|
| 04 rename | `publish-rename.sh` | `9.9.9` | copy in catalog; no Evidence |
| 05 non-golden | `publish-nongolden.sh` | `1.0.0` | negative control |
| 06 detect | `02-detect-lineage.sh` | pull all tags | already catalog-native pulls |
| 00 / 07–08 | `00-gen-keys.sh`, `gate-*.sh` | n/a | OIDC + setup-lab until rewritten |

Native already: 01 golden, 02 payments-api, 03 salestax-api (`publish-salestax-api.sh` is local-only).

Constants live in `lab/scripts/lib.sh`. Repeat them in workflow `env:` when going native so the YAML is readable without sourcing bash.

---

## 2026-08-25 — Customer docs leave-behind (this thread)

Human asked for **relevant JFrog documentation links** for a customer-facing deliverable, plus a section in the **repo root**, and tagged `.github/act/README.md`. Sources were live `docs.jfrog.com` `llms.txt` indexes (artifactory, governance, integrations, root), not training memory. Later 2026-08-30 sessions **added rows** (Docker Labels, AQL, Stored Packages GraphQL) to the same FINDINGS table — do not replace the section; extend it.

### Where it lives (do not duplicate a second full list)

| File | Role |
|---|---|
| `FINDINGS.md` → **Documentation (customer leave-behind)** | Canonical table. Share this with the customer. |
| `README.md` → **Documentation** | Points at that FINDINGS heading; also lab + act README for operators. Internal README later grew remotes/`public` rules (see 16:46). **Public** README must not mention remotes or `DECK_SPEC.md`. |
| `.github/act/README.md` → **Related documentation** | Short operator subset: OIDC vs token, `setup-jfrog-cli`, `jf evd create`, `jf docker`. Links back to FINDINGS + root README. |
| `DECK_SPEC.md` implementation note 7 | **No documentation slide.** After the meeting, send FINDINGS. Talking points stay verbal (`DECK_SPEC` speaker bank). |

### Groups in the FINDINGS table (original shape)

Docker/Artifactory (repos, OCI, remotes/virtuals, `jf docker`, properties, AQL) · Build Info · Evidence (setup, keys, CLI, predicate, GraphQL, optional GHA attestations) · AppTrust/Unified Policy (promote, lifecycle policies, custom Rego, CLI) · Adjacent SBOM/Curation (explicitly **not** lineage) · GitHub OIDC + `setup-jfrog-cli`.

Use HTML docs URLs (`…/docs/slug`, not `llms.txt` or `.md` index URLs).

### Do not

- Re-crawl all of `docs.jfrog.com` to rebuild this list from scratch; start from FINDINGS and add only new capabilities.
- Put the full link dump on slides or in the public-tree README (public still may link FINDINGS; it must not link DECK/SPEC/PROBLEM).
- Treat Curation/CVS/SBOM docs as Golden Image lineage proof.
