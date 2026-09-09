# Layer DiffID → Artifactory search

**What this proves:** A Golden Image `COPY` of a corporate CA (this lab: throwaway `acme-lab-root-ca.crt`) becomes a content-addressed layer. Descendants that `FROM` that Golden keep the same blob. Artifactory can inventory those images by **compressed layer SHA-256**, not by searching for PEM text or a “certificate” field.

**Lab-validated (linux/arm64, `golden-base:1.0.2` → `payments-api:2.0.0-ca-test` → `salestax-api:0.1.0-ca-test`):**

| Role | Value |
|---|---|
| CA `COPY` DiffID | `sha256:5cca43ff6519f6b8126fe431125f266a1af44589620dd57782643c4def23765d` |
| CA compressed digest (Artifactory) | `sha256:e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e` |
| Hex for AQL / checksum API | `e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e` |
| Blob filename | `sha256__e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e` |

linux/amd64 (GitHub Actions) will usually have a **different** compressed `HEX`. Repeat from the platform-select step with `architecture=="amd64"`.

---

## Two checksum families (do not mix)

| Name | Where it lives | Used for |
|---|---|---|
| **DiffID** | `docker image inspect` → `RootFS.Layers`; `docker history` pairing | Mapping a Dockerfile instruction (`COPY` cert) to a layer |
| **Compressed digest** | OCI manifest `layers[].digest`; Artifactory blob `sha256__<hex>` | Checksum API, AQL `sha256`, Build Info `module.artifact.item.name` |

Artifactory does **not** index DiffIDs. Searching for `5cca43ff…` in AQL will miss. Always translate DiffID → compressed digest on the **same image tag and platform**.

---

## Prerequisites

- Logged into the registry (`docker login` / `jf docker login`).
- `jq`, `curl`, `docker`, `jf`.
- `JF_URL` and `JF_ACCESS_TOKEN` for Artifactory REST.
- One image reference for the Golden catalog tag (example below).
- Rancher Desktop: `jf docker push --build-name` needs `DOCKER_HOST=unix://${HOME}/.rd/docker.sock` (not `/var/run/docker.sock`).

`docker buildx imagetools inspect` reads the **registry**, not only `docker image ls`. The tag must exist in Artifactory.

---

## 1. Pin the Golden image and pull the platform you will inspect

```bash
export IMG='tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.2'

docker login tomjpd2.jfrog.io
# or: jf docker login tomjpd2.jfrog.io --server-id tomjpd2

docker pull --platform linux/arm64 "$IMG"
```

**Does:** Authenticates, then stores the linux/arm64 image locally so `docker history` / `inspect` DiffIDs match that platform.

**Use the output:** Pull digest (index) is informational. The local tag `$IMG` is the input to every later local command.

**Significance:** Mixing a locally built tag that was never pushed with `imagetools inspect` causes `not found`. Mixing arm64 DiffIDs with an amd64 manifest produces a wrong `HEX`.

---

## 2. Confirm `imagetools --raw` is an index

```bash
docker buildx imagetools inspect --raw "$IMG" | jq 'keys'
```

**Does:** Shows top-level JSON keys of the registry object for `$IMG`.

**Use the output:** If you see `"manifests"`, `"mediaType"`, `"schemaVersion"`, this is an **OCI index** (multi-arch). Compressed layers are **not** here.

**Significance:** The next command must select a **platform manifest digest**, not inspect the index as if it had `.layers`.

---

## 3. Select the linux/arm64 image manifest (skip attestations)

```bash
export DIGEST=$(docker buildx imagetools inspect --raw "$IMG" | jq -r '
  .manifests[]
  | select(.platform.os=="linux" and .platform.architecture=="arm64")
  | select((.annotations["vnd.docker.reference.type"] // "") != "attestation-manifest")
  | .digest
')
echo "$DIGEST"
```

**Does:** Picks the real linux/arm64 image descriptor. Filters BuildKit attestation manifests (`unknown/unknown`).

**Use the output:** Exactly **one** line, e.g. `sha256:ddbcb479f097975eaede496eadf41e133284399bd4fe523f630786c10573dd06`. That value is `$DIGEST` for `${IMG}@${DIGEST}`.

**Significance:** Inspecting an attestation digest yields in-toto layers, not the CA `COPY`. Multiple lines mean the `select` is too loose.

---

## 4. Map Dockerfile instructions → DiffIDs (`docker history` + `RootFS.Layers`)

`docker image inspect` does **not** include history (`.Config.History` is null). History comes from `docker history`. History is **newest-first**; `RootFS.Layers` is **base-first**, so reverse non-empty history before zipping.

```bash
docker history --no-trunc --human=false --format '{{json .}}' "$IMG" \
| jq -s --argjson layers "$(docker image inspect "$IMG" --format '{{json .RootFS.Layers}}')" '
  [ .[] | select((.Size | tonumber) > 0) ]
  | reverse
  | to_entries[]
  | "\($layers[.key])\t\(.value.CreatedBy)"
'
```

**Does:** Drops metadata-only steps (`LABEL`, `CMD`, size 0). Aligns each filesystem layer with `CreatedBy`.

**Use the output:** Find the row whose `CreatedBy` contains `COPY` and `acme-lab-root-ca.crt`. Export that DiffID **once** (`sha256:` exactly once):

```bash
export DIFFID='sha256:5cca43ff6519f6b8126fe431125f266a1af44589620dd57782643c4def23765d'
```

**Significance:** This is the only step that answers “which layer is the CA `COPY`?” `LABEL` / `CMD` never appear. `RUN update-ca-certificates` is a **different** layer (trust-store rewrite, often arch-specific).

Expected Golden shape (this lab):

1. `ADD alpine-minirootfs-…` — OS
2. `RUN` marker + `apk add ca-certificates`
3. **`COPY certs/acme-lab-root-ca.crt …`** — CA fingerprint
4. `RUN update-ca-certificates`

---

## 5. List compressed layer digests on that platform manifest

```bash
docker buildx imagetools inspect --raw "${IMG}@${DIGEST}" \
  | jq '.layers[] | {digest, mediaType, size}'

docker buildx imagetools inspect --raw "${IMG}@${DIGEST}" \
  | jq -r '.layers[].digest'
```

**Does:** Prints registry blob digests (gzip layers) and media types.

**Use the output:** Keep only `application/vnd.oci.image.layer.v1.tar+gzip` (or similar `tar+gzip`). Count of those lines must equal the number of DiffID rows from step 4. A ~1KB layer is typically the cert `COPY`.

**Significance:** These `sha256:…` values are what Artifactory stores. `in-toto` / attestation media types are not CA layers.

---

## 6. Zip DiffID → compressed digest

```bash
paste \
  <(docker image inspect "$IMG" --format '{{range .RootFS.Layers}}{{println .}}{{end}}') \
  <(docker buildx imagetools inspect --raw "${IMG}@${DIGEST}" | jq -r '.layers[].digest')
```

**Does:** Column 1 = DiffID (local pull). Column 2 = compressed digest (same platform manifest). Same row index.

**Use the output:** The row whose column 1 equals `$DIFFID` is the Artifactory blob. Lab result:

```
sha256:5cca43ff…	sha256:e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e
```

```bash
export HEX='e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e'
```

**Significance:** If row counts differ, local `$IMG` is not `${IMG}@${DIGEST}` (wrong tag, stale pull, or index vs platform). Stop and re-pull `--platform linux/arm64`.

---

## 7. Search Artifactory by checksum (REST)

```bash
curl -sS -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
  "${JF_URL%/}/artifactory/api/search/checksum?sha256=${HEX}&repos=lineage-docker-local"
```

**Does:** `GET /artifactory/api/search/checksum` for SHA-256, limited to `lineage-docker-local`.

**Use the output:** `results[].uri` are storage URLs. The useful path looks like:

`…/golden-base/sha256:<platform-manifest>/sha256__<HEX>`

`…/_uploads/sha256__<HEX>` is a push sidecar; ignore for lineage slides.

**Significance:** Fast confirmation the blob exists. Does not by itself name “certificate”; it names a checksum you already bound to `COPY` in step 4.

---

## 8. Search Artifactory by AQL (`sha256` field)

AQL has **no** `actual_sha256` field (400 parse error). Use `sha256`. Body is `text/plain`, not JSON.

```bash
curl -sS -X POST \
  -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @- \
  "${JF_URL%/}/artifactory/api/search/aql" <<'EOF'
items.find({
  "repo": "lineage-docker-local",
  "sha256": "e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e"
}).include("repo","path","name","sha256")
EOF
```

Equivalent by blob **filename**:

```bash
curl -sS -X POST \
  -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @- \
  "${JF_URL%/}/artifactory/api/search/aql" <<'EOF'
items.find({
  "repo": "lineage-docker-local",
  "name": "sha256__e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e"
}).include("repo","path","name")
EOF
```

**Does:** Lists every item in the Docker local with that checksum / name.

**Use the output:** `path` is `<image>/<manifest-digest>` (or `_uploads`). Each distinct image name that is **not** `_uploads` is a catalog reference to the CA layer.

**Significance:** This is the inventory query for “who still carries the Golden CA layer?” It is rename-safe (digest does not change with tag). It is **not** a native “Golden compliance report.” Squash / `FROM scratch` + `COPY --from` drops the blob.

Before descendants are rebuilt from this Golden, you only see `golden-base`. After `FROM golden-base:1.0.2`, extra `path`s appear.

---


> *NOTE* The following steps were part of Tom's local testing and requried rebuilding some images off the Golden Image root after installing the dummy Certificates.  The following would not be required for images that were built off Golden and already hosted in Artifactory.


## 9. Rebuild payments-api locally (direct child)

Dockerfile `FROM` defaults to `golden-base:1.0.0`. Override with `--build-arg`. Do not use `publish-payments-api.sh` for this trial (defaults Golden `1.0.0`, attaches Evidence).

```bash
cd /Users/tomj/code/acme-docker-lineage

export GOLDEN_IMAGE='tomjpd2.jfrog.io/lineage-docker-local/golden-base:1.0.2'
export APP_IMAGE='tomjpd2.jfrog.io/lineage-docker-local/payments-api:2.0.0-ca-test'
export BUILD_NUM="local-$(date +%Y%m%d%H%M%S)"
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"

jf docker login tomjpd2.jfrog.io --server-id tomjpd2
docker pull --platform linux/arm64 "$GOLDEN_IMAGE"

docker build \
  --platform linux/arm64 \
  --build-arg "GOLDEN_IMAGE=${GOLDEN_IMAGE}" \
  --build-arg "GITHUB_RUN_NUMBER=0" \
  --build-arg "GITHUB_RUN_ID=0" \
  -t "${APP_IMAGE}" \
  lab/app-from-golden

jf docker push "${APP_IMAGE}" \
  --server-id tomjpd2 \
  --build-name acme-lineage-app \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env acme-lineage-app "${BUILD_NUM}" || true
jf rt build-publish acme-lineage-app "${BUILD_NUM}" --server-id tomjpd2
```

**Does:** Builds a unique tag `2.0.0-ca-test` from Golden `1.0.2`, pushes it, publishes Build Info.

**Use the output:** Push log `e0fe12d1a5d5: Layer already exists` means the CA blob was reused, not re-uploaded. Set `DOCKER_HOST` **before** `jf docker push --build-name` or the CLI cannot inspect the image (`unix:///var/run/docker.sock` on Rancher) and Build Info may omit layers even if `build-publish` succeeds.

**Significance:** Proves a cooperative child inherits the layer. Tag `2.0.0-ca-test` leaves catalog `payments-api:2.0.0` unchanged.

---

## 10. Validate the child locally (`docker history`)

```bash
docker history --no-trunc --human=false --format '{{json .}}' "$APP_IMAGE" \
| jq -s --argjson layers "$(docker image inspect "$APP_IMAGE" --format '{{json .RootFS.Layers}}')" '
  [ .[] | select((.Size | tonumber) > 0) ]
  | reverse
  | to_entries[]
  | "\($layers[.key])\t\(.value.CreatedBy)"
'
```

**Does:** Same pairing as step 4 on the child.

**Use the output:** Golden prefix (including CA `COPY` DiffID `5cca43ff…`) plus a new `RUN` for `/opt/app.txt`.

**Significance:** Tier 2 lineage (DiffID prefix) without Artifactory. Confirms AQL should grow a `payments-api` path.

---

## 11. Re-run AQL — expect payments-api

Repeat the AQL from step 8. Lab result included:

- `golden-base/_uploads` — ignore
- `golden-base/sha256:ddbcb479…` — Golden arm64
- `payments-api/sha256:1876bf6c…` — child **platform** manifest (not necessarily the index digest on the tag)

**Significance:** One blob, two image names. Artifactory did not copy a cert; it listed shared content.

---

## 12. Rebuild salestax-api locally (grandchild)

```bash
export DOCKER_HOST="unix://${HOME}/.rd/docker.sock"
export BASE_IMAGE='tomjpd2.jfrog.io/lineage-docker-local/payments-api:2.0.0-ca-test'
export SALESTAX_IMAGE='tomjpd2.jfrog.io/lineage-docker-local/salestax-api:0.1.0-ca-test'
export BUILD_NUM="local-$(date +%Y%m%d%H%M%S)"

jf docker login tomjpd2.jfrog.io --server-id tomjpd2
docker pull --platform linux/arm64 "$BASE_IMAGE"

docker build \
  --platform linux/arm64 \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "GITHUB_RUN_NUMBER=0" \
  --build-arg "GITHUB_RUN_ID=0" \
  -t "${SALESTAX_IMAGE}" \
  lab/app-from-intermediate

jf docker push "${SALESTAX_IMAGE}" \
  --server-id tomjpd2 \
  --build-name acme-lineage-salestax \
  --build-number "${BUILD_NUM}"

jf rt build-collect-env acme-lineage-salestax "${BUILD_NUM}" || true
jf rt build-publish acme-lineage-salestax "${BUILD_NUM}" --server-id tomjpd2
```

**Does:** Multi-hop `FROM` the ca-test payments-api, unique tag `0.1.0-ca-test`.

**Use the output:** Same as step 9. Parent must be the ca-test image, not `payments-api:2.0.0` (that tag may still be the pre-CA Golden).

**Significance:** Immediate parent is payments-api, not Golden. The CA layer still survives if layers were not squashed.

---

## 13. Validate the grandchild

```bash
export SALESTAX_IMAGE='tomjpd2.jfrog.io/lineage-docker-local/salestax-api:0.1.0-ca-test'

docker history --no-trunc --human=false --format '{{json .}}' "$SALESTAX_IMAGE" \
| jq -s --argjson layers "$(docker image inspect "$SALESTAX_IMAGE" --format '{{json .RootFS.Layers}}')" '
  [ .[] | select((.Size | tonumber) > 0) ]
  | reverse
  | to_entries[]
  | "\($layers[.key])\t\(.value.CreatedBy)"
'
```

**Expected prefix:** Alpine → marker/`apk` → **CA `COPY` (`5cca43ff…`)** → `update-ca-certificates` → payments-api `RUN` (`c831b2f3…`) → salestax `RUN` (`b729c071…`).

Re-run step 8 AQL. Lab result also included:

- `salestax-api/sha256:42e72b12…`

**Significance:** Multi-hop inventory from a single Golden CA blob checksum. Root-is-golden does not require the grandchild’s Dockerfile to mention `golden-base`.

---

## 14. Optional: Build Info AQL

Only after `jf docker push --build-name` successfully talked to the Docker API (Rancher `DOCKER_HOST`).

```bash
curl -sS -X POST \
  -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @- \
  "${JF_URL%/}/artifactory/api/search/aql" <<'EOF'
builds.find({
  "module.artifact.item.name": "sha256__e0fe12d1a5d59933bd16ee59ab3dc4746debb54b2ba7105c72f3b67e7a11fa3e"
}).include("name","number","repo","created")
EOF
```

**Does:** Finds published builds whose Docker module artifacts include that blob **name**.

**Use the output:** Ties the layer to CI build name/number (and the build UI URL from `build-publish`). Empty results mean layers were not collected (daemon socket) or the image was pushed with plain `docker push`.

**Significance:** Supporting signal, not required to prove the blob is on the image. Item AQL (step 8) is the catalog proof. Rename-without-CI still has no Build Info.

---

## Pitfalls (from this lab)

| Symptom | Cause | Fix |
|---|---|---|
| `imagetools inspect --raw`: `not found` | Tag only exists locally | Push, or inspect a published tag |
| `jq: Cannot iterate over null` on `.Config.History` | History is not in `docker image inspect` | Use `docker history` (step 4) |





