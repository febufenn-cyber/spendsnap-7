# Customer Support Runbook

## Intake

Every case must record company, authenticated requester, role, environment, request ID, affected receipt/claim/report/workflow/export ID, timestamp, expected behavior, actual behavior, and whether financial close or reimbursement is blocked. Never request secrets, OTP links, full card numbers, or unrelated receipt data.

## Triage

- **Urgent:** suspected tenant/privacy/security issue, altered evidence, unauthorized approval/export/billing, or company-wide outage.
- **High:** blocked submission/approval/export with no workaround, repeated provider failure, or period-close impact.
- **Normal:** configuration, onboarding, mapping, isolated extraction correction, or usability question.

Route urgent security cases to the incident runbook immediately.

## Safe investigation

1. Ask for request ID and record IDs, not screenshots containing unnecessary personal data.
2. Use role-scoped product views first.
3. Support access requires an explicit company grant with purpose, scope, start/end, and audit event.
4. Do not use service-role access casually or impersonate a user.
5. Preserve immutable extraction, policy, approval, export, agent, security, and billing history.
6. Explain when a correction creates a new version or submission rather than changing history.

## Common cases

- **Receipt failed:** check file type/size/signature, queue state, extraction run error, and retry eligibility.
- **Cannot verify:** resolve required fields and duplicate candidates; do not lower critical-field requirements.
- **Submission blocked:** inspect deterministic readiness and policy results; explain exact rule and exception path.
- **Approval missing:** verify eligible approver, delegation validity, assignment and outbox event; never bypass authentication.
- **Export rejected:** verify finance approval, accounting period lock, mappings, and idempotency key.
- **GST question:** explain completeness signal; refer tax eligibility to a qualified professional.
- **Agent advice wrong:** reject proposal, capture feedback, preserve run/model/prompt/context hash, and never apply silently.
- **Billing mismatch:** reconcile usage and signed provider events; do not edit processed event history.

## Resolution

State what changed, what evidence was preserved, whether any data was accessed, validation performed, known limitation, and next action. Link a permanent fix or documented workaround. Close only after the requester confirms or the defined support policy permits closure.
