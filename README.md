# Acme Docker lineage

Remotes: `origin` = full internal tree; `external` = stripped `public` branch (GitHub.com). Push `main` only to `origin`.

Working notes and lab for **Golden Image lineage** on the JFrog Platform: what Artifactory can prove today (layer diffs), what to capture next (**Evidence** + **Build Info**), and how **AppTrust** can gate promote later.

This is not a product that reports Golden Image compliance out of the box. The customer-facing answer is in [FINDINGS.md](FINDINGS.md). Slide copy lives in [DECK_SPEC.md](DECK_SPEC.md). The original ask is in [PROBLEM_STATEMENT.md](PROBLEM_STATEMENT.md) and [SPEC.md](SPEC.md).

## Documentation

**Leave-behind (JFrog product docs for the customer):** the curated link list is in [FINDINGS.md — Documentation](FINDINGS.md#documentation-customer-leave-behind). Use that section in the deliverable; do not invent extra claims from the titles.

**Reproduce the lab**

| Audience | Doc |
|---|---|
| Local scripts and image chain | [lab/README.md](lab/README.md) |
| GitHub Actions + local `act` (OIDC vs token, Rancher socket, runner image) | [.github/act/README.md](.github/act/README.md) |

## Quick start (lab)

See [lab/README.md](lab/README.md). Condensed:

```bash
./lab/scripts/00-gen-keys.sh
./lab/scripts/01-build-push.sh
./lab/scripts/02-detect-lineage.sh
./lab/scripts/03-apptrust-gate.sh
```
