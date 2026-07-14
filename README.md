# Spendsnap

> Turn employee receipts into reviewable, policy-checked, approved, accounting-ready expense evidence—without requiring a corporate card.

Spendsnap is an India-oriented, AI-assisted expense workflow built around a strict trust boundary: models may extract or advise, but deterministic rules and authenticated humans own financial decisions.

## Repository status

The repository implementation is complete through **Phase 8**:

```text
receipt upload
  → private storage and queued extraction
  → server file/hash and arithmetic validation
  → human resolution of critical fields
  → employee claim and immutable report submission
  → deterministic policy checks and scoped exceptions
  → authenticated manager and finance approval
  → GST document-readiness review
  → immutable checksummed Tally-compatible CSV export
  → tenant/security administration and audit evidence
  → guardrailed advisory agent
  → onboarding, trial, plans, usage and signed billing events
```

**This does not mean the product is live.** Infrastructure has not been provisioned, migrations have not been applied to a live database, provider credentials were unavailable, automated checks were not executed in this connector-only environment, and no customer financial data was processed.

See the [autonomous build completion report](docs/BUILD_COMPLETION_REPORT.md) and [production launch checklist](docs/LAUNCH_CHECKLIST.md).

## Trust boundaries

- The database owns financial state transitions and exact totals.
- Submitted, approved, exported and billing records preserve immutable evidence.
- Tenant boundaries use RLS plus explicit cross-table company checks.
- Critical receipt fields require human resolution.
- Duplicate detection creates candidates, never fraud accusations.
- GST readiness means document completeness, not tax-credit eligibility.
- Approval links require authentication; self-approval is forbidden.
- AI cannot approve, pay, determine tax eligibility, delete evidence, override policy or silently change financial facts.
- Billing webhooks require HMAC-SHA256 signatures, body limits, payload hashes and unique provider event IDs.

## Architecture

- **API and processing:** Cloudflare Workers, Hono and Cloudflare Queues
- **Data and identity:** Supabase Auth, Postgres, Row Level Security and private Storage
- **AI:** structured Anthropic vision extraction plus a separately guardrailed advisory agent
- **Web:** React, TypeScript and Vite multi-page build
- **Evidence:** immutable extraction, correction, policy, approval, export, security, agent and billing histories

## Product entry points

The web build produces:

| Entry | Purpose |
|---|---|
| `index.html` | Employee receipts, claims, reports and reviewer queue |
| `finance.html` | Finance review, GST readiness and Tally CSV export |
| `admin.html` | Members, invitations, security settings and audit evidence |
| `agent.html` | Advisory-only agent runs and human proposal confirmation |
| `commercial.html` | Onboarding, trial, usage and plan administration |

## Documentation

- [Build completion report](docs/BUILD_COMPLETION_REPORT.md)
- [Autonomous execution roadmap](docs/AUTONOMOUS_BUILD_ROADMAP.md)
- [Production launch checklist](docs/LAUNCH_CHECKLIST.md)
- [Deployment and rollback](docs/DEPLOYMENT.md)
- [Incident response](docs/INCIDENT_RESPONSE.md)
- [Support runbook](docs/SUPPORT_RUNBOOK.md)
- [Synthetic sales demo](docs/SALES_DEMO.md)
- [Security policy](SECURITY.md)
- [Privacy engineering principles](PRIVACY.md)
- [Phase 0 discovery framework](docs/phase-0/README.md)
- [Phase 1 receipt truth engine](docs/phase-1/README.md)
- [Phase 2 employee submission](docs/phase-2/README.md)
- [Phase 3 policy engine](docs/phase-3/README.md)
- [Phase 4 approval and product UI](docs/phase-4/README.md)
- [Phase 5 finance and export](docs/phase-5/README.md)
- [Phase 6 production hardening](docs/phase-6/README.md)
- [Phase 7 agent advisor](docs/phase-7/README.md)
- [Phase 8 commercial OS](docs/phase-8/README.md)

## Local validation

Requires Node.js 22 or newer.

### Backend

```bash
npm install
npm run check
```

### Web application

```bash
cd web
npm install
npm run typecheck
npm run build
```

The web artifact must contain all five HTML entry points listed above.

### Extraction evaluation

```bash
npm run evaluate -- research/gold.jsonl research/actual.jsonl research/report.json
```

## Major API groups

All `/v1` routes require a valid Supabase Bearer token.

- `/v1/receipts` — upload, processing, review, corrections and field resolution
- `/v1/duplicate-candidates` — finance/admin duplicate decisions
- `/v1/expenses` — claims, reports, assembly, submission and withdrawal
- `/v1/policies` — versioned rules, evaluation and exception requests
- `/v1/approvals` — assignments, immutable decisions and revisions
- `/v1/finance` — GST readiness, accounting workspace and exports
- `/v1/admin` — security settings, invitations, roles, deletion requests and audit export
- `/v1/agent` — advisory runs, proposals and human confirmation
- `/v1/commercial` — plans, onboarding, subscriptions, usage and product events
- `/webhooks/billing` — signed provider-neutral billing events

Operational endpoints:

- `GET /health`
- `GET /ready`

## Commercial hypotheses

| Area | Current hypothesis |
|---|---|
| Initial customer | Indian SMBs with repeated field or travel expense processing |
| Primary buyer | Finance manager, founder or accounting partner |
| Wedge | Verified receipt-to-accounting workflow with GST document readiness |
| Pricing | Company fee plus included usage; plan rows remain versionable experiments |
| First export | Tally-compatible UTF-8 CSV |
| Trust boundary | No cards, reimbursement payments, tax filing or autonomous approval |

## Before production

Apply every migration in filename order to a fresh non-production project, run the complete launch checklist, validate tenant isolation and concurrency, restore a backup, complete a real historical accounting import, independently review security and GST language, pass adversarial agent evaluation, integrate billing, and obtain a paid pilot.
