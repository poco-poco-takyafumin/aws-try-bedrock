---
name: bedrock-iac-review
description: Domain-specific review checklist for this repository's Amazon Bedrock Terraform infrastructure (docs/0X-*/infra). Covers IAM least-privilege / Guardrail-enforcement patterns, KMS key grants, CloudWatch/CloudTrail logging and PII-masking coverage, cost-allocation tagging, and recurring Terraform pitfalls (unstable ARNs, provider anti-patterns, cross-module default drift). Use whenever writing or reviewing Terraform that touches Bedrock Knowledge Base, Guardrails, IAM roles, CloudTrail/CloudWatch logging, KMS keys, or cost allocation in this repo — especially before `terraform apply`, or alongside /code-review, since CLAUDE.md requires human review of IAM, Guardrails, log-destination, and cost-management diffs.
---

# Bedrock IaC Review

Checklist distilled from two `/code-review` passes on this repo's first Bedrock Terraform
implementation (`docs/01-internal-rag-chatbot/infra`), generalized so the same mistakes don't
have to be rediscovered for use case 02/03. This supplements `/code-review`'s general-purpose
passes — run it specifically for the project-specific patterns below, which a generic reviewer
has no way to know are required here.

## How to use this checklist

1. For a diff touching `docs/0X-*/infra/**/*.tf` (or before `terraform apply`), go through every
   section below item-by-item against the actual changed files — don't just skim for style.
2. Confirm each candidate against the source (read the file, check the actual Resource/Condition/
   variable wiring) before reporting it — don't flag from memory of "this class of bug exists".
3. Report findings the same way `/code-review` does: call `ReportFindings` with `file`, `line`,
   `summary`, `failure_scenario`, and `verdict` once confirmed.

## IAM: Guardrail enforcement & least privilege

- **Every Bedrock action path is Guardrail-gated, not just `InvokeModel`.** If the app can call
  `RetrieveAndGenerate`, `Converse`, `InvokeModelWithResponseStream`, etc., each Allow statement for
  those actions needs the same `bedrock:GuardrailIdentifier` (+ `bedrock:GuardrailVersion`)
  Condition — a Guardrail requirement wired onto `InvokeModel` alone does not cover the others.
- **Pair every `StringNotEquals` safety-net Deny with a `Null` Deny.** IAM evaluates
  `StringNotEquals` as **false** (no deny) when the condition key is entirely absent from the
  request. A Deny meant to block "no Guardrail specified at all" needs a second statement:
  `Condition = { Null = { "bedrock:GuardrailIdentifier" = "true" } }`.
- **ID vs ARN must match between IAM and app code.** If the IAM condition compares against a
  Guardrail/model ARN, the Lambda env var (or SDK call) must pass the ARN, not the bare ID — check
  both sides of every Condition key by hand.
- **Guardrail version pinning must be consistent across every role that shares the guardrail**
  (AppRuntime, Developer, ...). Don't let one role check only `GuardrailIdentifier` while another
  also checks `GuardrailVersion` — the weaker one lets DRAFT/other versions through.
- **Don't allow the raw underlying resource next to its cost/routing wrapper.** If an Application
  Inference Profile (or similar wrapper) exists specifically to force cost-tagging or geo-routing,
  granting `bedrock:InvokeModel` on the bare foundation-model ARN too lets callers bypass the
  wrapper entirely.
- **Scope wildcard admin actions to settings-management only, and to the specific resource.**
  `logs:*` / `cloudtrail:*` / `s3:*` on `Resource = "*"` for an "Admin" role silently includes
  content-read actions (`GetLogEvents`, `FilterLogEvents`, `StartQuery`, `LookupEvents`,
  `GetObject`) that docs/00 reserves for Auditor only, and bucket-policy actions that should be
  scoped to one bucket, not the whole account.
- **Never use an STS session ARN as a persistent Principal.** `data.aws_caller_identity.this.arn`
  resolves to the *current apply's* assumed-role session and changes on every SSO re-login or CI
  run. Use a stable IAM role ARN (construct it from the role's deterministic name if referencing
  the module directly would create a circular module dependency).

## KMS / encryption

- **Both sides of a KMS grant, every time.** A role reading/writing an SSE-KMS bucket or a
  KMS-encrypted CloudWatch Log Group needs `kms:Decrypt`/`kms:GenerateDataKey*` on that key *in
  addition to* `s3:GetObject`/`logs:*` — `s3:GetObject` alone still 403s on decrypt.
- **CloudWatch Logs needs the regional service principal in the key policy**: `logs.<region>.
  amazonaws.com`, not the bare `logs.amazonaws.com` — otherwise the log group can never encrypt
  with a customer-managed key.
- **A new reader role (e.g. Auditor) needs KMS decrypt explicitly.** Bucket-policy read access does
  not imply KMS decrypt access; it's a separate, easy-to-forget grant.

## Logging / PII

- **Every logging destination needs equivalent protection, or a documented gap.** If requirements
  mandate logging to both CloudWatch Logs and S3, and only CloudWatch has a masking mechanism
  (e.g. CloudWatch Logs data protection has no S3 equivalent), say so explicitly in a comment and
  in the use case's `requirements.md` 未決事項 — don't let one protected destination create a false
  sense that both are covered.
- **`depends_on` the masking policy, not just a shared name.** If a data-protection/masking policy
  must exist before a logging configuration starts delivering data, add an explicit `depends_on` —
  sharing a log-group name string between two resources does not order them.
- **Regex PII detectors need a precision check.** A bare digit-count pattern (e.g. `\b\d{7}\b` for
  a bank account number) matches postal codes, invoice numbers, etc. Prefer requiring a nearby
  label/keyword over a bare pattern, and say so in the description.
- **Don't duplicate literal identifier lists across statements.** The same PII data-identifier ARN
  list used for "audit" and "redact" statements (or similar audit/enforce pairs) belongs in one
  `local`, referenced twice — otherwise a future edit to one silently diverges from the other.

## Cost management

- **A "must activate X" requirement needs an actual resource, not a README step.** If docs/00 or a
  use case's requirements say a cost-allocation tag must be enabled, add the Terraform resource for
  it (e.g. `aws_ce_cost_allocation_tag`) — a manual-only step means `plan`/`apply` never fails to
  remind anyone it wasn't done.
- **Centralize cross-module numeric defaults at the root.** Log retention days, budget thresholds,
  etc. should be root variables passed explicitly into every module that has its own default —
  don't let some modules silently fall back to a different built-in default than others received.

## Terraform / general hygiene

- **Trace configuration variables to the resource that actually consumes them.** A variable like
  `vector_dimension` used only in an OpenSearch index mapping, while the Bedrock Knowledge Base
  resource silently uses the embedding model's own default, will only surface as a runtime mismatch
  if the variable is ever changed — verify it's wired into every place that needs it.
- **Flag provider blocks whose config depends on a same-apply resource.** A `provider "x" {}` block
  reading an attribute of a resource created in the same module/apply (e.g. an OpenSearch Serverless
  collection endpoint) is a known Terraform anti-pattern; if inherited from a vendored sample and
  not worth restructuring, document the two-phase `apply -target=...` workaround for first deploy.
- **No new public entry point without an authorizer.** An API Gateway route, ALB listener, etc.
  created for this project must have an explicit auth mechanism from the start (`AWS_IAM`, JWT,
  Lambda authorizer, ...) — never ship an open chat/RAG endpoint as a "temporary Phase A" default.
- **Call out account/region-level singleton resources loudly.** Things like
  `aws_bedrock_model_invocation_logging_configuration` or an account-wide billing alarm apply once
  per AWS account×region, not per use case. Document this in the module and the use case's README
  so a second use case's Terraform doesn't silently overwrite the first's configuration.
