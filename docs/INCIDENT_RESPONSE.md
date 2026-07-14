# Incident Response Runbook

## Severity

- **SEV-1:** confirmed cross-tenant access, exposed secrets, altered financial evidence, unauthorized approval/export/billing action, or broad outage during financial close.
- **SEV-2:** material service degradation, queue backlog, provider outage, failed exports, or suspected limited data exposure.
- **SEV-3:** isolated defect with workaround and no confirmed confidentiality or integrity impact.

## First actions

1. Assign incident commander, security lead, communications lead, and scribe.
2. Preserve request IDs, deployment SHA, audit/security events, queue messages, provider logs, database timestamps, and affected object hashes.
3. Stop further harm using the narrowest reversible control: disable route/provider secret, pause queue consumer, revoke support grant, expire invitation, block origin, or roll back deployment.
4. Never rewrite or delete financial, approval, export, security, agent, or billing evidence during containment.
5. Determine companies, users, records, time range, providers, and data classes affected.
6. Rotate compromised credentials and invalidate sessions when justified.
7. Notify accountable owners and follow contractual/legal notification requirements.

## Scenario playbooks

### Tenant isolation failure

Disable affected route, preserve proof, identify query/RLS path, test all roles across two synthetic companies, patch with a forward migration, rotate exposed credentials, and independently review related tables.

### Extraction or AI regression

Disable the model endpoint or pin the prior model/prompt. Keep original documents and failed runs. Re-run only through a new immutable run. Do not overwrite verified facts.

### Approval or export integrity issue

Pause decision/export routes, identify submission/workflow/batch IDs, verify immutable snapshots/checksums, void through forward evidence rather than editing history, and notify finance owners.

### Billing webhook issue

Disable or rotate the webhook secret, preserve raw hashes/event IDs, replay only verified events through a controlled tool, reconcile subscription states, and confirm duplicate events remain idempotent.

### Provider outage

Expose degraded status, stop retry storms, use queue backoff/dead letters, preserve pending work, and resume idempotently after health is restored.

## Recovery and closure

- Verify containment and recovery with reproducible tests.
- Record root cause, contributing factors, timeline, customer impact, evidence, and residual risk.
- Add regression tests, monitoring, runbook changes, and accountable follow-up dates.
- Conduct a blameless review for SEV-1/2 incidents.
- Close only after customer, legal, security, finance, and engineering obligations are satisfied.
