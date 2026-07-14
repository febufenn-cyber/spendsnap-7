# Spendsnap

> Employees snap receipts; Spendsnap converts them into reviewable, auditable expense reports without requiring a corporate card.

Spendsnap is an AI-assisted expense-report product seed. Its initial India-specific hypothesis is GST-aware receipt processing, while customer segment, accounting destination, pricing, and GST value remain evidence-driven decisions.

## Current implementation

The repository contains two completed backend phases and an in-progress third phase:

```text
Phase 1 — Receipt Truth Engine
signed receipt upload
  → private company-scoped storage
  → extraction queue
  → file/hash verification
  → structured vision extraction
  → deterministic validation and duplicate checks
  → human field resolution
  → verified receipt evidence

Phase 2 — Employee Submission and Report Assembly
verified receipt evidence
  → employee-confirmed expense claim
  → category/project/cost-centre context
  → draft report assembly
  → database readiness validation
  → exact totals grouped by currency
  → immutable submitted report snapshot
  → finance-visible evidence

Phase 3 — Deterministic Policy Engine (in progress)
draft claim/report
  → versioned company policy rules
  → explainable warning/block evaluations
  → scoped exception requests
  → locked submission-time re-evaluation
  → immutable policy evidence
```

The architecture uses:

- Cloudflare Workers, Hono, and Cloudflare Queues;
- Supabase Auth, Postgres, Row Level Security, and private Storage;
- Anthropic vision through a forced structured extraction tool;
- immutable extraction, correction, resolution, submission, policy, and audit records;
- optimistic versions and database row locks for concurrent report edits.

The AI cannot approve expenses, determine tax-credit eligibility, pay reimbursements, invent exchange rates, or overwrite accepted values.

## Documentation

- [Autonomous remaining-phase build roadmap](docs/AUTONOMOUS_BUILD_ROADMAP.md)
- [Phase 0 — discovery and validation](docs/phase-0/README.md)
- [Phase 1 — receipt truth engine](docs/phase-1/README.md)
- [Phase 1 threat model](docs/phase-1/threat-model.md)
- [Phase 1 provisioning runbook](docs/phase-1/runbook.md)
- [Phase 2 — employee submission and report assembly](docs/phase-2/README.md)
- [Phase 3 — deterministic policy engine](docs/phase-3/README.md)
- [Supabase setup and isolation checks](supabase/README.md)
- [Receipt evaluation data contract](research/README.md)
- [Architecture decisions](decisions/)

The command `build` means: verify the current mainline state, finish Phase 3, then execute Phases 4–8 sequentially under the roadmap's preflight, testing, commit, publication, and confirmation protocol. External operations that cannot be performed must be disclosed rather than implied.

## Local validation

Requires Node.js 22 or newer.

```bash
npm install
npm run check
```

To compare model output with a human-verified corpus:

```bash
npm run evaluate -- research/gold.jsonl research/actual.jsonl research/report.json
```

## API surface

### Receipt evidence

- `GET /health`
- `POST /v1/receipts/upload-intents`
- `POST /v1/receipts/:receiptId/complete`
- `GET /v1/receipts/:receiptId`
- `GET /v1/receipts/:receiptId/review`
- `POST /v1/receipts/:receiptId/corrections`
- `POST /v1/receipts/:receiptId/resolutions`
- `POST /v1/duplicate-candidates/:candidateId/resolve`

### Employee expenses

- `GET /v1/expenses/dimensions?companyId=...`
- `POST /v1/expenses/claims/from-receipt`
- `GET /v1/expenses/claims?companyId=...&status=draft`
- `GET /v1/expenses/claims/:claimId`
- `PATCH /v1/expenses/claims/:claimId`
- `POST /v1/expenses/reports`
- `GET /v1/expenses/reports?companyId=...&status=draft`
- `GET /v1/expenses/reports/:reportId`
- `POST /v1/expenses/reports/:reportId/items`
- `DELETE /v1/expenses/reports/:reportId/items/:claimId?expectedVersion=...`
- `POST /v1/expenses/reports/:reportId/submit`
- `POST /v1/expenses/reports/:reportId/withdraw`

All `/v1` routes require a valid Supabase Bearer token. Receipt field resolution and duplicate decisions require finance or admin. Employees control their own claims and reports; manager, finance, admin, and auditor roles may read company report evidence.

## Business hypothesis

| Area | Hypothesis |
|---|---|
| Monetization | Company base fee plus active usage; validate against per-seat and receipt-volume pricing |
| Initial customer | Indian SMBs with repeated manual employee-expense processing |
| Product wedge | Verified receipt-to-accounting workflow; test whether GST awareness materially improves purchase intent |
| Competition | High; generic receipt scanning and approvals are not sufficient differentiation |
| Trust boundary | AI-assisted reporting only; no cards, money movement, tax advice, or autonomous approval |

## Status

Phase 1 and Phase 2 are code-complete in the repository. Phase 3 is partially implemented and must pass its roadmap exit gate before Phase 4 begins. Infrastructure has **not** been provisioned or deployed by these commits. Before real customer data, apply all migrations in a non-production Supabase project, create Cloudflare queues, configure secrets, run tenant-isolation and concurrency tests, execute the full repository check, and validate a representative consented receipt/report corpus.
