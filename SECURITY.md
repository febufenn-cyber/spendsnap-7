# Security Policy

## Reporting a vulnerability

Do not open a public issue for vulnerabilities involving authentication, tenant isolation, financial evidence, secrets, billing, or personal data. Contact the repository owner through a private GitHub security advisory or the private security contact published by the deployed service. Include affected component, reproduction steps, impact, and whether data was accessed. Do not retain or redistribute customer data.

## Supported code

Until versioned releases exist, only the latest commit on `main` is supported. The repository is not evidence that a production deployment is secure; environment configuration, provider controls, migrations, monitoring, and operational testing are required.

## Security boundaries

- Supabase user sessions plus RLS control browser-facing data access.
- Service-role, Anthropic, billing, and provider secrets stay inside Worker secrets.
- Receipt objects are private and company scoped.
- Financial predictions, corrections, resolutions, policies, approvals, exports, security events, agent runs, and billing events retain immutable evidence.
- Approval links require authentication; self-approval is blocked.
- AI is advisory and cannot approve, pay, determine tax eligibility, delete evidence, or silently mutate financial facts.
- Billing webhooks require a bounded raw body, HMAC-SHA256 signature, payload hash, and unique provider event ID.

## Required production controls

- Explicit origin allowlist and static-host CSP.
- Secret rotation, least-privilege provider accounts, protected production branches, reviewed migrations, and rollback plans.
- Two-company tenant isolation tests, independent penetration testing, backup restoration, queue/dead-letter monitoring, and incident exercises.
- Security events, audit exports, support access, invitations, role changes, and deletion requests must be reviewed regularly.

## Out of scope for the current repository

Formal compliance certification, SSO/SAML, managed SOC operations, production key custody, legal conclusions, and provider-specific infrastructure are not delivered by source code alone.
