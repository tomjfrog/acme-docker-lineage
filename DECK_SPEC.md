# Deck spec: Golden Image lineage — path forward

Feed this file to a subagent that implements JFrog-branded slides. Do not invent extra slides, extra claims, or a longer narrative. Design system: `jfrog-slide-design-system` skill.

---

## Brief

| Field | Value |
|---|---|
| Working title | Golden Image compliance: from forensics to AppTrust |
| Length | **10 slides** (narrative + Q&A; do not exceed 11) |
| Format | JFrog-branded deck (Google Slides from official template, or PPTX that matches the design system). Prefer the official Google Slides template copy workflow in the skill. |
| Audience | **Customer-facing.** Platform, AppSec, and container owners who already understand Golden Images, rename, and lost `FROM`. |
| Goal | Align on what JFrog can do **today**, walk the **tiered** path (Evidence + Build Info MVP → AppTrust), then answer **their questions** in their wording with a few lines each. |
| Tone | Short. Honest. Advisory. No filler. No “journey,” “unlock,” or “empower.” |

### What this deck is not

The customer already knows the problem. **Do not** spend slides explaining what a Golden Image is, why `FROM` disappears after rename, or “does this artifact still root in the catalog?” One clause of context on the title slide is enough.

### One-line thesis

Today, Golden Image lineage is a manual layer-diff exercise — Artifactory cannot report compliance. Capture provenance with Evidence and Build Info now; govern it with AppTrust later.

### Phrases to keep (use verbatim where a slide specifies them)

- The only way to determine lineage **today** is comparing layer diffs.
- This works. It is also slow, custom, and easy to get wrong.
- Artifactory has **no native report** for Golden Image compliance.
- Evidence and Build Info are the MVP: capture provenance so queries against Artifactory get cheaper and reliable.
- AppTrust is the enterprise governance layer on that same metadata.

### Do not

- Re-teach the problem statement (Golden Image definition, Dockerfile contract, rename story).
- Present layer-diff matching as the recommended operating model or a JFrog product feature.
- Claim Artifactory can already report Golden Image compliance.
- Frame this as a signing-first story. Do not mention Compliant Version Selection.
- Claim EOL / refresh-SLA reporting, or Docker Hub mirror origin for historical derived images.
- Promise AppTrust as something they must buy to start. Evidence + Build Info is the start; AppTrust is the ideal future state.

---

## Design constraints (mandatory)

Follow `jfrog-slide-design-system` v1.2.0:

- Dark canvas `#0d1117`, titles `--accent-green` (`#40c057`), body white, captions `#a0aec0`.
- Cards `#1a2332` / feature `#1a3a2a` / risk `#3d1a1a`. Radius 8px. Bullets `▪` only.
- Open Sans. No extra logos, SURGE badges, or background chrome if using the official template master.
- Footer metadata on content slides (italic, secondary): `Evidence Collection | Build Info | AppTrust`
- Every text block: **max 3 short bullets or 2 sentences**, except Q&A slides (see pattern below). If copy overflows, cut words — do not shrink fonts below the design system.
- Diagrams: rounded boxes, `#1a2332` fill, `#2d3748` stroke; highlight recommended path in green; today’s forensic path in `#a0aec0` or risk red only for limits.

### Q&A slide pattern (slides 4–6)

- Layout: stacked cards, **2–3 questions per slide**. Never 1 question per slide. Never 4+.
- **Question text is verbatim.** Copy the string from [Customer questions (verbatim)](#customer-questions-verbatim--do-not-edit) with no paraphrase, no trim, no synonym swap (“a Golden Image” is not “an Acme Golden Image”). Wrap onto multiple lines if needed; shrink the question slightly before you cut a word.
- **Answer the question that was asked.** Yes/no questions start with **Yes**, **No**, or **Partially**. Multi-part questions address **each** part (e.g. path, digest, layers, build info, SBOM, OCI — not a generic “it depends”).
- Answer body: `--text-secondary`, **2–4 short lines**. Honest “not in this solution” is allowed. Do not pad with a product pitch.

If building PowerPoint instead of Google Slides: same colors, type, and layouts; 16:9 is acceptable only if the official template cannot be used. Still do not invent a custom brand.

### Customer questions (verbatim — do not edit)

Use these strings as the question on the slide. Do not rewrite.

1. What can JFrog tell us today about the upstream/base image source for container images already stored or pulled through Artifactory?
2. Can JFrog determine whether a derived image originally came from an Acme Golden Image if the image was renamed, retagged, or pushed to another repository?
3. What metadata or build information must be captured going forward to make lineage tracking reliable?
4. Can JFrog distinguish Golden Image usage from non-Golden Image usage using repository path, digest, image layers, build info, SBOM, or OCI metadata?
5. Can JFrog report on non-Golden Images and identify whether they came from mirrored public repositories?
6. Can JFrog identify images that are outdated, EOL, or not refreshed within a given timeframe?
7. What is the minimum viable solution JFrog recommends for current-state discovery, and what is the long-term solution for governance and enforcement?
8. What are the gaps or limitations Acme should expect with historical images already built without required metadata?

---

## Slide list

1. Title
2. What we can do today: layer diffs
3. A tiered path
4. Q&A — What we can say today (3 questions)
5. Q&A — Signals, metadata, MVP vs long-term (3 questions)
6. Q&A — Adjacent asks (2 questions)
7. Near term — Evidence and Build Info (MVP)
8. Future state — AppTrust governance
9. Gate screenshot (placeholder)
10. Close

---

## Slide 1 — Title

**Layout:** 3.1 Title Slide

**Title (green, large):** Golden Image compliance

**Subtitle (secondary):** From layer forensics to governed provenance

**Optional third line (small, secondary):** What JFrog can do today — and the tiered path forward

**Visual:** JFrog logo per master only. No extra art.

**Speaker notes:** They know Golden Images and the rename/`FROM` gap. This meeting is the path: honest today, MVP next, AppTrust as the control plane.

---

## Slide 2 — What we can do today: layer diffs

**Layout:** 3.5 Risk / Alert, with two short bullets under the block **or** 3.2 Content (left text + right visual)

**Title:** Today, lineage is a layer-diff exercise

**Risk label:** Current state

**Body (keep short):** The only way to determine lineage **today** is comparing image layer diffs (DiffIDs) against a Golden Image catalog. That can reconstruct ancestry after rename. It is also a custom, labor-intensive process — and Artifactory has **no native report** for Golden Image compliance.

**Under the block (exactly three bullets):**

▪ Build and maintain a Golden DiffID catalog  
▪ Extract and match layers for every candidate image  
▪ Treat “no match” as inconclusive (squash, rebase, `FROM scratch`) — not a clean fail

**Do not** introduce Evidence, Build Info, or AppTrust on this slide.

**Right visual (if 3.2):** Two stacked layer lists: Golden prefix present vs no overlap. Caption: *Forensic. Not a product report.*

**Speaker notes:** Acknowledge it works for scoping what is already in Artifactory. Be explicit: this is not something you click in the UI. It is engineering time, edge cases, and no promote hook.

---

## Slide 3 — A tiered path

**Layout:** 3.3 Feature Card Grid (3 cards, left to right)

**Title:** Three tiers. Same question. Better answers over time.

**Subtitle (white, one line):** Do not wait for the last tier to start capturing provenance.

**Cards (exactly these, in this order):**

1. **Today — forensics**  
   Layer-diff matching against the Golden catalog. Scopes the backlog. Custom, slow, not governed.

2. **Near term — MVP**  
   Use **Evidence** and **Build Info** on every publish. Provenance becomes queryable metadata in Artifactory.

3. **Future — governance**  
   **AppTrust** consumes that same metadata and enforces Golden Image policy at promote/release.

**Caption (italic green):** Each tier builds on the last. You do not throw away Evidence when AppTrust turns on.

**Speaker notes:** Frame as a program, not a rip-and-replace. Tier 1 is honesty about today. Tier 2 is the recommendation to start. Tier 3 is the enterprise-grade end-state. Next three slides answer their questions in their words.

---

## Slide 4 — Q&A: What we can say today

**Layout:** Three stacked Q&A cards (full width). Question = card title (**verbatim**). Answer = card body.

**Title:** Your questions — what JFrog can say today

**Card 1 — question (verbatim):** What can JFrog tell us today about the upstream/base image source for container images already stored or pulled through Artifactory?

**Card 1 — answer:** Today: digest, ordered layers, and whatever Build Info or Evidence was already published. Artifactory does **not** retain the original `FROM` name, and it has **no native report** of upstream/base source or Golden Image compliance. Stored locals: custom layer-diff against a Golden catalog. Pulled-through remotes: path of the cached artifact only — that is not lineage for a derived app image.

**Card 2 — question (verbatim):** Can JFrog determine whether a derived image originally came from an Acme Golden Image if the image was renamed, retagged, or pushed to another repository?

**Card 2 — answer:** **Yes** for renamed or retagged images in Artifactory — digest and layer chain do not change, so a Golden layer prefix can still match. **Partially** if pushed to another repository: another Artifactory Docker local, query by digest; ACR/ECR (or any registry outside Artifactory) only if that same digest is re-pushed here. Evidence does **not** follow a new name — look up by digest.

**Card 3 — question (verbatim):** What are the gaps or limitations Acme should expect with historical images already built without required metadata?

**Card 3 — answer:** Acme should expect **no queryable provenance**: no `FROM`, no Evidence, no useful Build Info. The only option is labor-intensive layer-diff, which is **inconclusive** after squash, rebase, or `FROM scratch` — not a clean “not Golden.” Images that never entered Artifactory are out of scope unless they are re-pushed.

**Speaker notes:** Read the question as written, then the answer. Do not skip “pulled through,” “Acme Golden Image,” or “another repository.”

---

## Slide 5 — Q&A: Signals, metadata, path forward

**Layout:** Three stacked Q&A cards (full width).

**Title:** Your questions — how we distinguish, and what to capture next

**Card 1 — question (verbatim):** Can JFrog distinguish Golden Image usage from non-Golden Image usage using repository path, digest, image layers, build info, SBOM, or OCI metadata?

**Card 1 — answer:** **Partially — signal by signal.** Repository path: **no** (teams publish to their own repos). Digest: identity key, not Golden by itself. Image layers: **yes** (Golden DiffID prefix; heuristic). Build info: **yes**, if CI recorded the base. SBOM: **no** (package inventory ≠ base image). OCI metadata: **weak** (history/commands, not `repo/name:tag` of the parent).

**Card 2 — question (verbatim):** What metadata or build information must be captured going forward to make lineage tracking reliable?

**Card 2 — answer:** Digest-pinned `FROM`. **Build Info** on every `jf docker push` / `build-publish`. Signed **Evidence** on the image digest: child digest, immediate base name + digest, preferably `root_golden_digest` (or a walk to the Acme Golden catalog). Name and tag are not enough.

**Card 3 — question (verbatim):** What is the minimum viable solution JFrog recommends for current-state discovery, and what is the long-term solution for governance and enforcement?

**Card 3 — answer:** **Current-state discovery (MVP):** Evidence + Build Info on new publishes so Artifactory can be queried; layer-diff only to scope historical images that have no metadata. **Long-term governance and enforcement:** AppTrust / Unified Policy promote gates that require that same derived-from-Golden Evidence. Same metadata. Stronger control.

**Speaker notes:** Card 1 must name all six signals. Card 3 must answer both halves: discovery MVP **and** long-term enforcement.

---

## Slide 6 — Q&A: Adjacent asks

**Layout:** Two stacked Q&A cards (full width). Risk-tint (`--bg-risk`) is acceptable if it stays readable.

**Title:** Your questions — what this solution does not cover yet

**Card 1 — question (verbatim):** Can JFrog report on non-Golden Images and identify whether they came from mirrored public repositories?

**Card 1 — answer:** **Partially.** Report on non-Golden Images: **yes** — classify as not derived from the Acme Golden catalog (no layer prefix / no Golden Evidence). Identify whether they came from mirrored public repositories: **no**, not as a first-class finding for derived app images. That needs a mirror catalog or remote-cache join, which is not this path.

**Card 2 — question (verbatim):** Can JFrog identify images that are outdated, EOL, or not refreshed within a given timeframe?

**Card 2 — answer:** **No** — not in this lineage solution. JFrog cannot identify outdated, EOL, or unrefreshed images from Golden Image provenance work. Do identity first (Golden vs not). Freshness/EOL is a later discussion (golden versions, artifact age, Xray/Catalog).

**Speaker notes:** Answer both verbs in card 1: *report on non-Golden* vs *identify mirrored public origin*. Card 2 is a clean no.

---

## Slide 7 — Near term: Evidence and Build Info (MVP)

**Layout:** 3.2 Content (left text + right visual) **or** 3.4 Two-column (2–3 rows)

**Title:** MVP: capture provenance with what you already have

**Intro (one sentence):** Evidence and Build Info are existing JFrog capabilities. Use them so Artifactory can be queried for lineage instead of reverse-engineering layers.

**Bullets (exactly these):**

▪ **Build Info** — publish with `jf docker push --build-name/--build-number` so the image is tied to a build, not only a tag  
▪ **Evidence** — signed lineage on the digest: child image, immediate base, preferably root Golden digest  
▪ **Query** — look up provenance by package/digest in Artifactory; rename no longer orphans the story

**Right visual:** Small flow: `CI pin FROM @sha256` → `Build Info` + `Evidence` → `query by digest`. No AppTrust gate on this slide.

**Footer:** This is the system of record for new publishes. Layer diffs remain a backstop for images that never got metadata.

**Speaker notes:** MVP is operational efficiency: stop paying the layer-diff tax on every new image. Historical images without metadata stay in the forensic bucket. Multi-hop: walk parent Evidence or store `root_golden_digest` on every hop.

---

## Slide 8 — Future state: AppTrust

**Layout:** 3.6 Architecture / Diagram

**Title:** Future state: AppTrust as enterprise governance

**Intro (one line, under title):** AppTrust does not replace Evidence or Build Info. It **governs** them.

**Diagram (left-to-right):**

```
Evidence + Build Info          AppTrust / Unified Policy         Promote
already on the package         derived-from-golden required      pass → PreProd / Prod
queryable in Artifactory       entry gate, block mode            fail → stop
```

- Green path: Evidence present → **pass**
- Red path: Evidence missing → **block**
- Caption (italic green): *Same predicates. Promote-time enforcement. No re-architecture of the CI contract.*

**Do not** show layer diffs on this slide.

**Speaker notes:** Ideal end-state: Golden Image compliance is a gate, not a spreadsheet. AppTrust reads Evidence at promote. Present → move. Missing → block. If Evidence only names an intermediate, require a walk or `root_golden_digest` in CI — do not try to recurse the golden catalog inside the gate.

---

## Slide 9 — Gate screenshot

**Layout:** 3.2 Content (left text + right visual)

**Title:** The gate reads the Evidence you already attached

**Left:**

▪ Near term: teams query Evidence / Build Info  
▪ Future: AppTrust blocks promote unless that Evidence is on the version  
▪ No second provenance model

**Right — required image slot (do not omit this slide):**

Draw a rounded card (`--bg-card`, `#2d3748` border, 8px radius) filling the right column. Centered inside:

**`[PLACEHOLDER: Gate Screenshot]`**

Secondary caption under the label (italic, `--text-secondary`):  
*AppTrust / Unified Policy dry-run — derived-from-golden pass vs fail. Replace this box with the live gate screenshot before customer delivery.*

**Placeholder rules:**

- Always ship this slide. Never delete it because the PNG is missing.
- Do **not** fake an AppTrust UI. The box is an asset drop zone only.
- When the screenshot is ready, replace the placeholder in place. Preferred asset: `assets/apptrust-gate-screenshot.png` (pass + fail, or two frames). Until then, keep the labeled box.

**Speaker notes:** Drop the tomjpd2 PreProd dry-run here: `payments-api` pass, `rogue-api` fail. Same Evidence the MVP slide just described.

---

## Slide 10 — Close

**Layout:** 3.1 Title Slide (closing) **or** 3.4 three-row table

**Title:** Start capturing. Govern when ready.

**Three lines (centered, or three rows):**

| Now | Next | Later |
|---|---|---|
| Layer diffs only to scope the existing estate. No native compliance report. | Evidence + Build Info on every image publish. Query provenance in Artifactory. | AppTrust gates on that same metadata. Enterprise Golden Image enforcement. |

**Optional last line (green, small):** Forensics for the past. Evidence for the record. AppTrust for the control plane.

**Speaker notes:** Ask for agreement on the MVP CI contract first. AppTrust is the destination, not the admission ticket.

---

## Copy bank (use; do not expand)

- Today’s only method = compare layer diffs / DiffIDs to a Golden catalog.
- That method = technically possible, labor-intensive, custom tooling, inconclusive on squash/rebase.
- Artifactory = no existing/native Golden Image compliance report.
- MVP = Evidence + Build Info on publish; provenance becomes queryable metadata; efficiency vs layer forensics.
- Layer diffs = backstop for historical images only.
- Future = AppTrust / Unified Policy as enterprise governance, consuming Evidence + Build Info (not a new lineage model).
- Sequence = forensics now → capture provenance next → enforce at promote later.

---

## Customer talking points

Speaker / Q&A bank from `FINDINGS.md`. **Not extra slides.** Do not add a talking-points slide; do not put CVS on a slide. Implementation roll-up: **FINDINGS.md → Customer implementation checklist**.

1. **Capability you want is lineage/provenance tracking**, not signing-first.
2. JFrog natively contributes **Build Info**, **Evidence Collection** (incl. OCI/SLSA attestations), artifact properties, and content-addressed Docker storage for layer correlation; Xray adds SBOM/security context.
3. **Rename does not erase lineage** at the digest/layer level.
4. **Multi-hop** (child built from child) still needs root-is-golden proof: layer-prefix vs golden catalog, Evidence walk, or `root_golden_digest` in CI predicates — validated in lab run `20260817152017`.
5. **DiffIDs scope the issue; they are not the product path.** Prefix matching proves ancestry is recoverable (incl. rename), but operationalizing it as the system of record is a large custom engineering program (catalog, scale, edge cases, no native promote gate, weaker audit). See FINDINGS.md [Why DiffID prefix is not the ideal primary solution](FINDINGS.md#why-diffid-prefix-is-not-the-ideal-primary-solution).
6. **Start with Evidence today** (CI contract + queryable signed lineage) even if AppTrust is not licensed yet; use DiffID forensics only as a backstop for non-cooperating teams.
7. **AppTrust later:** same derived-from Evidence feeds promote gates—no re-architecture. Detect images that “could / should have been” on golden via Tier 2 catalog matching + Tier 3 gates when available.
8. **Tier 3 works:** AppTrust / Unified Policy can **block promote** into `dockerlineage-PreProd` unless derived-from lineage Evidence is on the application version’s packages — validated with `payments-api` (pass) vs `rogue-api` (fail).
9. **CVS** (verbal only if asked): addresses compliant *library* version selection — adjacent governance story for languages, not Docker base lineage.
10. **Golden `LABEL`s are searchable today:** Artifactory copies inherited OCI labels to `docker.label.*` on each descendant `manifest.json`. AQL (not Stored Packages GraphQL) inventories golden + children + multi-hop + rename; non-golden misses. Layer squash does not break this; scratch/`COPY --from` does. See FINDINGS.md [OCI golden-marker labels](FINDINGS.md#oci-golden-marker-labels--searchable-today).

---

## Implementation notes for the subagent

1. Read this spec. Treat `PROBLEM_STATEMENT.md` as background for the *speaker*, not slide copy. Do not put the Golden Image explainer on a slide.
2. Apply `jfrog-slide-design-system`. Copy official template `1vbrkJFCU9Kr6Gz4a_GZF40u7oPN96Z15LGeOpj7hT8s` if using Google Slides API.
3. Build slides 1–10 in order. Slides 4–6 are Q&A. Paste each customer question **verbatim** from the numbered list in this spec. Answers must address the question directly (Yes/No/Partially; every named signal or clause). Slide 9 must include the `[PLACEHOLDER: Gate Screenshot]` card until a real PNG replaces it. Do not omit that slide. Do not invent a fake AppTrust UI.
4. Keep titles exactly as specified unless a character limit in the template requires a trivial trim.
5. Deliver: deck URL or file path, plus a one-line confirmation of slide count.
6. Do not add an agenda slide, a problem-statement recap, a “why JFrog” slide, or a CVS slide.
7. Do not add a documentation slide. If the customer asks for links after the meeting, point them to **FINDINGS.md → Documentation (customer leave-behind)** (same list as the repo root README). Use [Customer talking points](#customer-talking-points) for verbal answers only.
