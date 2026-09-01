# TODO(rego-gate): custom Unified Policy template — not wired into step 07 yet.
#
# Today step 07 uses built-in template 1003 (predicateType presence only).
# This file is the intended next gate: inspect derived-from Evidence *contents*.
#
# Create via POST /unifiedpolicy/api/v1/templates (package must be curation.policies).
# Then create a rule from that template and bind it in ensure_policy.
#
# Docs:
#   https://docs.jfrog.com/governance/docs/custom-templates
#   https://docs.jfrog.com/governance/docs/rego-policy-code
#   https://docs.jfrog.com/governance/reference/templatescreate
#
# Limits that matter for this lab:
#   - Evaluation input is OneModel for *this* application version (no http.send).
#   - Recursion is prohibited, so a parent-chain Evidence walk is not a good
#     fit here. Prefer CI writing derived_from_golden / root_golden_digest on
#     every hop (see FINDINGS.md).
#   - Confirm predicate JSON field paths against a live OneModel dump before
#     enabling the gate (evidenceConnection / predicate payload shape).
#
# Intended checks (once input paths are confirmed):
#   1. At least one evidence predicateType == lineage URI (param).
#   2. Unmarshaled predicate has derived_from_golden == true
#      OR a non-empty root_golden_digest.
#   3. Optional: image_digest matches the packaged Docker digest.
#
# Positive control: payments-api (derived_from_golden: true).
# Negative control: rogue-api (no lineage Evidence) — still fails.
# Stretch negative: Evidence of the right type with derived_from_golden: false
#   (today salestax-api is that shape — 1003 would pass; this template should fail
#    unless we also write root_golden_digest on salestax-api).

package curation.policies

import rego.v1

# Rule-time parameter; default matches lab/scripts/lib.sh PREDICATE_TYPE_LINEAGE.
lineage_type := object.get(input, "predicateType", "https://jfrog.com/evidence/acme-docker-lineage/derived-from/v1")

app_version := object.get(object.get(input, "data", {}), "applications", {})

# Placeholder: replace with the real OneModel evidenceConnection walk.
# Keep this allow.should_allow = false until the path is proven against a dump.
allow := {
	"should_allow": false,
	"explanation": "TODO(rego-gate): wire OneModel evidenceConnection; do not enable this template in bootstrap until should_allow is implemented against live input.",
	"violated_findings": ["unwired-template"],
}
