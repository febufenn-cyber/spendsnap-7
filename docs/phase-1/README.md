# Phase 1 — Receipt Truth Engine

> Build the evidence layer that turns an uploaded receipt into structured, reviewable, auditable financial data.

Phase 1 is deliberately narrower than the original MVP. It does not build expense reports, approval chains, reimbursements, billing, cards, or autonomous policy decisions. Those layers are only valuable when the receipt data underneath them can be trusted.

## Strategic position

The visible product is an AI expense assistant. The hidden product is a financial evidence system.

A receipt pipeline must answer four questions before downstream automation is allowed:

1. **What document was submitted?**
2. **What did the model infer from it?**
3. **Which fields are safe, uncertain, inconsistent, or unsupported?**
4. **Who confirmed or corrected each financially meaningful value?**

The core principle is:

`document evidence → immutable prediction → deterministic validation → human confirmation → accepted fact`

AI output is never written directly over accepted financial data.

## Primary user outcome

An authenticated employee can upload a supported receipt image and receive a structured extraction that:

- preserves the original file and its hash;
- records the model, prompt version, and raw response;
- exposes field-level confidence and evidence;
- detects arithmetic inconsistencies;
- flags exact or likely duplicate submissions;
- routes critical or uncertain fields to review;
- stores every correction as a new auditable event;
- never silently changes an accepted value.

## Supported Phase 1 document boundary

Initially supported:

- JPEG receipts;
- PNG receipts;
- WebP receipts;
- one image per receipt submission;
- files no larger than 7.5 MB before base64 encoding;
- English and mixed-language merchant text where the model can interpret it.

Explicitly deferred:

- HEIC conversion;
- PDFs and multi-page hotel folios;
- handwritten cash books;
- bank and card statement matching;
- line-level personal/business splitting;
- tax-credit eligibility decisions;
- automatic reimbursement;
- policy approval and accounting export.

The upload boundary is intentionally strict. Unsupported documents fail visibly instead of entering the system with fabricated certainty.

## Receipt lifecycle

```text
upload_pending
      ↓
received
      ↓
queued
      ↓
extracting
      ↓
extracted ──────────────┐
      ↓                  │
needs_review             │
      ↓                  │
verified                 │
                         │
failed ── retry ─────────┘

Any non-final state may become rejected or archived through an explicit action.
```

Transitions are validated in the database. An application bug must not be able to move a receipt from `upload_pending` directly to `verified`.

## Architecture

```text
Client
  │
  │ 1. Request signed upload intent
  ▼
Cloudflare Worker + Hono
  │
  ├─ authenticates Supabase JWT
  ├─ creates receipt record
  ├─ creates short-lived signed upload URL
  └─ returns company-scoped storage path
  │
  │ 2. Client uploads directly to Supabase Storage
  │
  │ 3. Client confirms upload
  ▼
Worker validates object existence
  │
  ├─ marks receipt received
  └─ enqueues extraction job
  ▼
Cloudflare Queue consumer
  │
  ├─ downloads original through service client
  ├─ computes server-side SHA-256
  ├─ creates immutable extraction run
  ├─ calls Claude vision with forced structured tool output
  ├─ validates arithmetic and confidence policy
  ├─ stores field predictions
  ├─ creates duplicate candidates
  └─ marks receipt extracted / needs_review / failed
  ▼
Review API and future UI
```

The system begins as a modular monolith: one Worker deployment with clear domain boundaries. Separate services are deferred until load, ownership, or reliability requires them.

## Security and trust boundaries

- The browser never receives the Supabase service-role key or Anthropic API key.
- User-facing database access uses the employee's Supabase JWT and Row Level Security.
- Internal extraction uses a service client only inside the Worker.
- Storage paths begin with the company UUID and receipt UUID.
- Signed upload URLs are short-lived and restricted to one object path.
- File type and declared size are validated before an upload intent is created.
- Actual object existence, content hash, and byte size are checked server-side.
- Receipt text is untrusted data, never an instruction to the model or application.
- Raw model output is retained for debugging and audits, but is not treated as accepted truth.
- Critical fields require human confirmation even at high model confidence.

## Field review policy

Fields are grouped by consequence, not by model convenience.

### Critical — always require confirmation

- total amount;
- currency;
- invoice number when used for duplicate or tax review;
- taxable value;
- CGST, SGST, and IGST;
- GSTIN;
- payment status when introduced later.

### Contextual — review when uncertain

- merchant name;
- invoice date;
- category suggestion;
- document type;
- business-purpose suggestion;
- project or cost centre when introduced later.

### Derived checks — never accepted from the model alone

- arithmetic consistency;
- duplicate status;
- policy compliance;
- tax-credit eligibility;
- fraud conclusions.

A model may provide evidence for these checks, but deterministic code or a human makes the final classification.

## Duplicate strategy

Phase 1 distinguishes:

1. **Exact-content duplicate** — server-computed SHA-256 matches another company receipt.
2. **Near-image duplicate** — deferred until perceptual hashing is added.
3. **Semantic duplicate candidate** — normalized merchant, date, currency, amount, and invoice number match.

The system creates a candidate and reason. It never labels an employee fraudulent automatically.

## Extraction output contract

The extractor returns a typed object containing:

- document type and image-quality assessment;
- merchant name;
- invoice number;
- invoice date;
- currency;
- subtotal and total;
- taxable value;
- CGST, SGST, IGST, and other tax;
- GSTIN;
- line-item summary where readable;
- warnings;
- a confidence score and evidence snippet for each extracted field.

Confidence is a routing signal, not proof of correctness.

## API surface

### `GET /health`

Reports process health and build metadata. It does not test third-party dependencies.

### `POST /v1/receipts/upload-intents`

Creates a receipt record and a signed upload URL.

Required inputs:

- company ID;
- original filename;
- MIME type;
- byte size;
- capture source;
- optional capture timestamp.

### `POST /v1/receipts/:receiptId/complete`

Confirms that the object upload completed, verifies the expected object exists, stores the client-provided hash as an untrusted hint, and enqueues extraction.

### `GET /v1/receipts/:receiptId`

Returns the authenticated user's company-scoped receipt and extraction state.

### Future Phase 1 slice

- review fields;
- submit corrections;
- compare duplicate candidates;
- retry failed extraction;
- archive a receipt.

## Database entities

- `companies`
- `company_memberships`
- `receipts`
- `receipt_pages`
- `extraction_runs`
- `extracted_fields`
- `field_corrections`
- `duplicate_candidates`
- `audit_events`

Important separation:

`receipt file ≠ model prediction ≠ accepted field value ≠ correction history`

## Observability

Every request and extraction run includes:

- request ID;
- receipt ID;
- company ID;
- extraction-run ID;
- model and prompt version;
- start and finish timestamps;
- normalized error code;
- retry count;
- final state.

Logs must not contain full receipt images, API keys, authorization headers, or unrestricted raw personal data.

## Failure handling

- Upload intent creation is idempotent only when an explicit idempotency key is added in a later slice.
- Queue messages may be delivered more than once; extraction processing must detect completed or active runs.
- A model timeout creates a failed extraction run without deleting the receipt.
- Retrying creates a new extraction run rather than mutating the old one.
- Invalid structured output is stored as a failed run and never partially accepted.
- Hash mismatch is treated as an integrity warning and requires review.
- Unsupported MIME types are rejected before upload.

## Exit criteria

Phase 1 is complete only when:

- tenant isolation is covered by RLS policies and tests;
- supported files can complete the signed-upload flow;
- server-side file hashing is recorded;
- extraction runs are immutable and versioned;
- every predicted field carries confidence and review status;
- totals and tax arithmetic are checked deterministically;
- critical fields cannot become verified without human action;
- exact duplicate submissions are surfaced as candidates;
- retries do not overwrite prior runs;
- failure states are visible and recoverable;
- automated tests cover lifecycle, money validation, confidence routing, and fingerprints;
- a representative receipt corpus can be evaluated without placing customer files in Git.

## What Phase 1 does not prove

Completing this phase proves that Spendsnap can create trustworthy receipt records. It does not prove:

- customer demand;
- GST input-credit eligibility;
- accounting-export compatibility;
- policy accuracy;
- manager approval behavior;
- willingness to pay.

Those remain Phase 0 and later-phase validation responsibilities.

## Implementation slices

1. **Foundation** — Worker, Hono, environment contract, health endpoint, request IDs.
2. **Secure intake** — Supabase JWT verification, signed upload intents, object confirmation, queueing.
3. **Truth schema** — receipt lifecycle, extraction history, field predictions, corrections, RLS, storage policies.
4. **Extraction engine** — Claude vision adapter, strict output contract, server hashing, deterministic checks.
5. **Verification API** — review and correction endpoints, accepted-value projection, duplicate decisions.
6. **Evaluation harness** — corpus manifest, expected values, field metrics, regression report.

This repository implementation delivers slices 1–4 and the domain foundation for slices 5–6.
