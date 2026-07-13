# Phase 1 Operator Runbook

This runbook provisions and exercises the receipt truth engine. Repository code alone does not create Supabase resources, Cloudflare Queues, secrets, or a deployed Worker.

## Prerequisites

- Node.js 22 or newer;
- a Supabase project and Supabase CLI session;
- a Cloudflare account and Wrangler login;
- an Anthropic API key with access to the configured vision-capable model;
- separate non-production and production projects.

## Install and validate

```bash
npm install
npm run check
```

`npm run check` runs strict TypeScript checking, compiles the Worker, and executes the domain and schema contract tests.

## Apply Supabase migrations

Link to a non-production project first:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push
```

Then perform the two-user/two-company negative isolation tests listed in `supabase/README.md`. A successful migration is not proof that RLS behaves correctly for real JWTs.

## Create Cloudflare queues

```bash
npx wrangler login
npx wrangler queues create spendsnap-extractions
npx wrangler queues create spendsnap-extractions-dlq
```

The names must match `wrangler.jsonc`.

## Configure secrets

```bash
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ANTHROPIC_MODEL
```

Do not put the service-role or Anthropic key in `wrangler.jsonc`, `.env`, browser code, mobile code, screenshots, logs, or support tickets.

For local development, copy `.env.example` to `.dev.vars` and supply non-production values. `.dev.vars` is ignored by Git.

## Create the first company

After signing in through Supabase Auth, call the authenticated RPC:

```sql
select public.create_company_with_admin('Spendsnap Test Company');
```

The function creates the company and assigns the current authenticated user as admin atomically.

## Run locally

```bash
npm run dev
```

Check health:

```bash
curl http://localhost:8787/health
```

## Receipt flow

All `/v1` calls require a Supabase access token.

### 1. Create an upload intent

```bash
curl -X POST http://localhost:8787/v1/receipts/upload-intents \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "companyId":"<company-uuid>",
    "originalFilename":"receipt.jpg",
    "mediaType":"image/jpeg",
    "sizeBytes":123456,
    "source":"camera",
    "capturedAt":"2026-07-13T10:00:00+05:30"
  }'
```

### 2. Upload directly to the signed storage URL

Use the returned signed URL/token with the Supabase signed-upload flow. Do not invent another object path.

### 3. Complete the upload

Compute SHA-256 on the client as an integrity hint, then call:

```bash
curl -X POST http://localhost:8787/v1/receipts/<receipt-uuid>/complete \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"clientSha256":"<64-lowercase-or-uppercase-hex-characters>"}'
```

The queue consumer downloads the object, verifies its file signature and size, recomputes SHA-256, runs extraction, performs deterministic checks, and persists an immutable run.

### 4. Read the review bundle

```bash
curl http://localhost:8787/v1/receipts/<receipt-uuid>/review \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
```

### 5. Submit a correction

```bash
curl -X POST http://localhost:8787/v1/receipts/<receipt-uuid>/corrections \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "corrections":[{
      "fieldName":"total",
      "previousFieldId":"<extracted-field-uuid>",
      "correctedValue":"1180.00",
      "reason":"Confirmed from the printed grand total"
    }]
  }'
```

### 6. Resolve fields as finance/admin

A resolution selects either the immutable prediction or a submitted correction:

```bash
curl -X POST http://localhost:8787/v1/receipts/<receipt-uuid>/resolutions \
  -H "Authorization: Bearer $FINANCE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "decisions":[{
      "fieldName":"total",
      "source":"correction",
      "sourceId":"<correction-uuid>"
    }],
    "finalize":false
  }'
```

Set `finalize` to `true` only after resolving every field marked `requires_review`. Verification is blocked while duplicate candidates remain open.

### 7. Resolve a duplicate candidate

```bash
curl -X POST http://localhost:8787/v1/duplicate-candidates/<candidate-uuid>/resolve \
  -H "Authorization: Bearer $FINANCE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"resolution":"not_duplicate","note":"Different employees attended separate meetings"}'
```

## Evaluate model or prompt changes

Prepare human-verified and actual JSONL files as documented in `research/README.md`:

```bash
npm run evaluate -- research/gold.jsonl research/actual.jsonl research/report.json
```

Do not promote a new model or prompt based only on aggregate accuracy. Inspect regressions in total, currency, invoice number, GSTIN, and tax fields separately.

## Deployment

After non-production integration tests pass:

```bash
npm run deploy
```

Before production traffic, record the deployed commit SHA in `BUILD_SHA`, verify queue/DLQ bindings, test one successful and one intentionally failed extraction, and confirm that logs contain identifiers rather than receipt contents.

## Recovery

- Provider or storage failures create a failed extraction run and retry through the queue.
- Retrying creates a new immutable extraction run.
- Non-retryable file-integrity failures are acknowledged and remain visible as failed receipts.
- Do not edit extraction rows manually. Repair through a reviewed migration or explicit administrative tool that emits audit events.
- Inspect the dead-letter queue before replaying messages; correct the root cause first.

## Production blockers still requiring evidence

- migrations applied and integration-tested against a real Supabase project;
- real queue and dead-letter behavior tested;
- representative receipt corpus evaluated;
- prompt/model version approved against release thresholds;
- human review UI implemented or API exercised by an internal operator;
- retention, deletion, incident response, and support-access policies approved;
- external security review before handling broad customer financial data.
