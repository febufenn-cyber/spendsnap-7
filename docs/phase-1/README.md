# Phase 1 — Receipt Truth Engine

> Turn a submitted receipt into structured, reviewable, auditable financial evidence.

Phase 1 deliberately stops before reports, policy approval, reimbursement, cards, billing, or accounting export. Those workflows should consume verified receipt facts rather than raw AI output.

## Core rule

```text
document evidence
  → immutable model prediction
  → deterministic validation
  → human correction or confirmation
  → verified fact
```

AI output never overwrites an accepted value. Every model attempt, correction, resolution, duplicate decision, and lifecycle change remains traceable.

## Implemented flow

```text
authenticated employee
  → signed company-scoped upload
  → private Supabase Storage
  → Cloudflare extraction queue
  → file signature, size, and SHA-256 verification
  → forced structured Anthropic vision extraction
  → arithmetic and confidence checks
  → exact/semantic duplicate candidates
  → employee correction proposals
  → finance/admin field resolution
  → verified receipt
```

## Supported boundary

Supported now:

- JPEG, PNG, and WebP;
- one image per receipt;
- maximum 7.5 MB;
- field-level confidence and evidence;
- merchant, invoice, date, currency, subtotal, taxes, total, GSTIN, and line-item extraction;
- exact decimal arithmetic checks;
- exact-content and semantic duplicate candidates.

Deferred:

- HEIC, PDF, and multi-page conversion;
- bank/card transaction matching;
- perceptual image hashing;
- personal/business line splitting;
- policy approval;
- accounting export;
- reimbursement and money movement;
- GST input-credit eligibility decisions.

Unsupported documents fail visibly instead of entering the system with fabricated certainty.

## Trust boundaries

- User-facing calls use Supabase JWTs and RLS.
- Service-role and Anthropic keys remain inside the Worker.
- Storage paths begin with company UUID and receipt UUID.
- The server verifies actual bytes rather than trusting filename, MIME declaration, size, or client hash.
- Text inside receipts is untrusted data and cannot issue instructions to the model or application.
- The model can only submit a typed extraction object; it cannot approve, pay, delete, or change policy.
- Totals, currency, invoice number, GSTIN, taxable value, and tax fields always require human resolution.
- Any contextual field with low confidence or a deterministic warning also requires resolution.
- Verification is blocked while required-review fields or duplicate candidates remain open.

See [the threat model](threat-model.md) for the adversarial analysis.

## Receipt lifecycle

```text
upload_pending → received → queued → extracting
                                      ├→ needs_review → verified → archived
                                      ├→ extracted → verified
                                      └→ failed → queued (new immutable attempt)
```

The database trigger rejects illegal transitions. Application code cannot jump directly from upload to verified.

## Data separation

The schema deliberately keeps these concepts separate:

```text
receipt file
≠ extraction run
≠ predicted field
≠ correction proposal
≠ accepted field resolution
≠ duplicate decision
≠ audit event
```

Core tables:

- `companies`, `company_memberships`;
- `receipts`, `receipt_pages`;
- `extraction_runs`, `extracted_fields`;
- `field_corrections`, `field_resolutions`;
- `duplicate_candidates`, `audit_events`.

RLS protects tenant reads and user writes. Database scope triggers additionally prevent cross-company foreign-key relationships, including service-side mistakes that RLS alone would not catch.

## API

- `GET /health`
- `POST /v1/receipts/upload-intents`
- `POST /v1/receipts/:receiptId/complete`
- `GET /v1/receipts/:receiptId`
- `GET /v1/receipts/:receiptId/review`
- `POST /v1/receipts/:receiptId/corrections`
- `POST /v1/receipts/:receiptId/resolutions`
- `POST /v1/duplicate-candidates/:candidateId/resolve`

All `/v1` routes require authentication. Finance/admin authority is checked inside security-definer database functions before resolution or final verification.

## Evaluation and release safety

The repository includes:

- strict TypeScript checking;
- lifecycle, confidence, arithmetic, fingerprint, image-signature, and evaluation tests;
- schema contract tests for RLS, tenant integrity, immutable history, service-only extraction RPCs, and verification gates;
- per-field corpus evaluation with overall and critical-field metrics;
- CI on pushes to `main` and pull requests.

Run:

```bash
npm install
npm run check
npm run evaluate -- research/gold.jsonl research/actual.jsonl research/report.json
```

Use `MIN_CRITICAL_ACCURACY` and `MIN_OVERALL_COVERAGE` to make evaluation failures block a release.

## Implementation status

Implemented in the repository:

1. Worker/API foundation;
2. secure intake and queueing;
3. tenant-safe truth schema;
4. structured extraction engine;
5. correction, field-resolution, duplicate-resolution, and final-verification API;
6. corpus evaluation harness, tests, CI, and operator documentation.

Not performed by repository commits:

- creating or linking a Supabase project;
- applying migrations to a live database;
- creating Cloudflare queues;
- configuring secrets;
- deploying the Worker;
- running real two-company RLS integration tests;
- evaluating a representative, consented receipt corpus.

Follow the [operator runbook](runbook.md). Phase 1 should not be declared production-ready until those integration and evidence gates pass.

## What this phase does not prove

The implementation establishes a trustworthy receipt-processing foundation. It does not prove customer demand, willingness to pay, GST eligibility, accounting compatibility, policy accuracy, or manager behavior. Those claims require Phase 0 evidence and later workflow phases.
