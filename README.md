# Spendsnap

> Employees snap receipts; Spendsnap converts them into reviewable, auditable expense reports without requiring a corporate card.

Spendsnap is an AI-assisted expense-report product seed. Its initial India-specific hypothesis is GST-aware receipt processing, while customer segment, accounting destination, pricing, and GST value remain evidence-driven decisions.

## Current implementation

The repository contains two implemented backend phases:

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
```

The architecture uses:

- Cloudflare Workers, Hono, and Cloudflare Queues;
- Supabase Auth, Postgres, Row Level Security, and private Storage;
- Anthropic vision through a forced structured extraction tool;
- immutable extraction, correction, resolution, submission, and audit records;
- optimistic versions and database row locks for concurrent report edits.

The AI cannot approve expenses, determine tax-credit eligibility, pay reimbursements, invent exchange rates, or overwrite accepted values.

## Documentation

- [Phase 0 — discovery and validation](docs/phase-0/README.md)
- [Phase 1 — receipt truth engine](docs/phase-1/README.md)
- [Phase 1 threat model](docs/phase-1/threat-model.md)
- [Phase 1 provisioning runbook](docs/phase-1/runbook.md)
- [Phase 2 — employee submission and report assembly](docs/phase-2/README.md)
- [Supabase setup and isolation checks](supabase/README.md)
- [Receipt evaluation data contract](research/README.md)
- [Architecture decisions](decisions/)

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

The Phase 1 and Phase 2 code, migrations, tests, and documentation are committed to `main`. Infrastructure has **not** been provisioned or deployed by these commits. Before real customer data, apply all migrations in a non-production Supabase project, create Cloudflare queues, configure secrets, run tenant-isolation and concurrency tests, execute the full repository check, and validate a representative consented receipt/report corpus.
