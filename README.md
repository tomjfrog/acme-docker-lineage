# Acme Docker lineage

Lab and findings for **Golden Image lineage** on the JFrog Platform: what Artifactory can prove today (layer diffs), what to capture next (**Evidence** + **Build Info**), and how **AppTrust** can gate promote later.

This is not a product that reports Golden Image compliance out of the box. The write-up is in [FINDINGS.md](FINDINGS.md).

## Documentation

Product docs used in this recommendation are listed in [FINDINGS.md — Documentation](FINDINGS.md#documentation-customer-leave-behind).

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
