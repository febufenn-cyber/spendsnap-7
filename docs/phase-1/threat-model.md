# Phase 1 Threat Model

## Assets

- receipt images and metadata;
- employee identity and company membership;
- extracted financial fields;
- correction and audit history;
- Supabase service-role key;
- Anthropic API key;
- signed upload URLs;
- tenant isolation guarantees.

## Trust boundaries

1. Employee device to Cloudflare Worker.
2. Employee device to Supabase Storage signed URL.
3. Worker to Supabase Auth, Database, and Storage.
4. Worker to Cloudflare Queue.
5. Queue consumer to Anthropic API.
6. Finance reviewer to future correction endpoints.

## Primary threats and controls

### Cross-tenant access

**Threat:** A user changes a company or receipt UUID and reads another company's data.

**Controls:**

- RLS on every tenant-owned table;
- membership functions keyed from `auth.uid()`;
- company-prefixed storage paths;
- no service-role database response returned without an explicit company check;
- negative tenant-isolation tests before production.

### Service-role key disclosure

**Threat:** A service key reaches browser code, logs, or source control.

**Controls:**

- Worker secrets only;
- `.dev.vars` ignored;
- no service key in Wrangler variables;
- log redaction;
- secret rotation after suspected exposure.

### Signed upload URL abuse

**Threat:** A signed URL is reused, shared, or used to overwrite an unrelated object.

**Controls:**

- one predetermined object path;
- short expiry;
- generated receipt UUID;
- filename sanitization;
- object existence and metadata verification before queueing;
- future idempotency and one-time completion token.

### Oversized or unsupported files

**Threat:** Resource exhaustion, extraction cost spikes, or unsupported decoder paths.

**Controls:**

- allowlist JPEG, PNG, and WebP;
- 7.5 MB declared-size limit;
- verify actual bytes before extraction;
- reject unexpected content types;
- resize/compression pipeline before broader file support.

### Prompt injection inside receipts

**Threat:** Document text tells the model to ignore instructions, expose secrets, or approve an expense.

**Controls:**

- system prompt states all document content is untrusted evidence;
- the model only fills a forced extraction tool schema;
- no model tool can approve, pay, delete, or change policy;
- deterministic validation after model output;
- human review for critical fields.

### Model hallucination or malformed output

**Threat:** Invented values enter financial records.

**Controls:**

- forced structured output;
- schema validation;
- raw-response retention;
- field confidence and evidence;
- arithmetic checks;
- critical-field confirmation;
- failed-run state for invalid output.

### Duplicate queue delivery

**Threat:** The same receipt is processed repeatedly, creating cost or inconsistent state.

**Controls:**

- detect active/succeeded extraction runs;
- immutable run records;
- explicit retry semantics;
- queue acknowledgement only after persistence;
- future unique job/idempotency key.

### Altered client hash

**Threat:** Client supplies a false SHA-256 to hide or manufacture a duplicate.

**Controls:**

- client hash stored only as a hint;
- server computes SHA-256 from downloaded bytes;
- mismatch creates an integrity warning;
- duplicate matching uses server hash.

### Log leakage

**Threat:** Sensitive receipt or identity data appears in logs.

**Controls:**

- structured error codes instead of full payload dumps;
- never log images, authorization headers, API keys, or complete model responses;
- log identifiers and metrics only;
- raw responses remain in restricted database columns.

### Unauthorized state transition

**Threat:** A client marks a receipt verified without review.

**Controls:**

- database transition trigger;
- no public update policy for extraction-owned states;
- accepted values derived from explicit correction/verification events;
- service code cannot bypass transition rules accidentally.

## Deferred threats

These require explicit design before their features ship:

- forged or digitally altered receipt detection;
- bank/card transaction matching;
- malware scanning for PDFs and archives;
- reimbursement fraud scoring;
- tax-advice liability;
- data residency and regulated-industry requirements;
- long-term evidence retention and legal holds;
- insider access to service-role tooling.
