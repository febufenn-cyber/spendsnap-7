# Spendsnap

> Employees snap receipts; Spendsnap converts them into reviewable, auditable expense data without requiring a corporate card.

Spendsnap is an AI-assisted expense-report product seed inspired by the workflow category pioneered by products such as Emburse. Its initial India-specific hypothesis is GST-aware receipt processing, but Phase 0 treats the customer segment, accounting destination, pricing, and GST value as evidence-driven decisions rather than assumptions.

## Current implementation

The repository now contains **Phase 1: Receipt Truth Engine**:

```text
signed receipt upload
  → private company-scoped storage
  → extraction queue
  → server file/hash verification
  → structured vision extraction
  → deterministic arithmetic and duplicate checks
  → field-level review queue
  → employee correction proposals
  → finance/admin resolution
  → verified receipt evidence
```

The architecture uses:

- Cloudflare Workers, Hono, and Cloudflare Queues;
- Supabase Auth, Postgres, Row Level Security, and private Storage;
- Anthropic vision through a forced structured extraction tool;
- immutable extraction, correction, resolution, duplicate, and audit records.

The AI cannot approve expenses, determine tax-credit eligibility, pay reimbursements, or overwrite accepted values.

## Documentation

- [Phase 0 — discovery and validation](docs/phase-0/README.md)
- [Phase 1 — receipt truth engine](docs/phase-1/README.md)
- [Phase 1 threat model](docs/phase-1/threat-model.md)
- [Provisioning and operator runbook](docs/phase-1/runbook.md)
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

- `GET /health`
- `POST /v1/receipts/upload-intents`
- `POST /v1/receipts/:receiptId/complete`
- `GET /v1/receipts/:receiptId`
- `GET /v1/receipts/:receiptId/review`
- `POST /v1/receipts/:receiptId/corrections`
- `POST /v1/receipts/:receiptId/resolutions`
- `POST /v1/duplicate-candidates/:candidateId/resolve`

All `/v1` routes require a valid Supabase Bearer token. Final field resolution and duplicate decisions require the finance or admin role.

## Original business hypothesis

| Area | Hypothesis |
|---|---|
| Monetization | Company base fee plus active usage; validate against per-seat and receipt-volume pricing |
| Initial customer | Indian SMBs with repeated manual employee-expense processing |
| Product wedge | Verified receipt-to-accounting workflow; test whether GST awareness materially improves purchase intent |
| Competition | High; generic receipt scanning and approvals are not sufficient differentiation |
| Trust boundary | AI-assisted reporting only; no cards, money movement, tax advice, or autonomous approval |

## Status

The code, migrations, tests, and runbook are committed. Infrastructure has **not** been provisioned or deployed by these commits. Before real customer data, apply migrations in a non-production Supabase project, create the queues, configure secrets, run tenant-isolation tests, and evaluate a representative consented receipt corpus.
