# Privacy and Data-Handling Principles

This file is an engineering statement, not a final legal privacy notice. A qualified legal reviewer must adapt it for the deployed operator, jurisdictions, vendors, contracts, and customer promises.

## Data processed

Spendsnap may process account identity, company membership, receipt images, merchant and travel information, expense claims, policy results, approvals, GST-related document fields, accounting mappings, exports, audit/security events, usage, support grants, agent context, and billing references.

Receipt data can reveal location, purchases, relationships, travel, and personal items. It must be treated as confidential financial and behavioral information.

## Principles

- Collect only data required for the configured workflow.
- Keep raw receipt objects private and tenant scoped.
- Do not expose service-role, model, billing, or provider secrets to browsers.
- Do not train models on customer data without explicit contractual permission.
- Redact email, payment-like numbers, tokens, and secrets from agent context.
- Preserve financial evidence and corrections for auditability, while applying documented retention schedules.
- Record deletion requests separately from destructive execution so legal and financial retention can be reviewed.
- Make human access, human verification, AI processing, subprocessors, storage location, retention, and deletion behavior transparent.
- Keep advertisers and unrelated parties outside customer financial data.

## Roles and access

Employees see their own operational records. Managers, finance, admins, and auditors receive role-specific access. Support access must be company-approved, purpose-limited, scoped, time-bounded, revocable, and audited.

## AI boundary

Model output is untrusted until validated. The advisor receives redacted structured context rather than raw image bytes and cannot approve expenses, decide tax eligibility, move money, delete evidence, or silently change financial facts.

## Retention and deletion

Each company has versioned receipt and audit retention settings. Production deletion requires an approved request, dependency and legal-retention review, backup consideration, operator authorization, and execution evidence. Source code does not automatically erase production financial evidence.

## Customer obligations

Customers must have a lawful basis to submit employee and vendor information, configure appropriate roles, disclose company monitoring and expense policies, and avoid uploading unrelated sensitive material.
