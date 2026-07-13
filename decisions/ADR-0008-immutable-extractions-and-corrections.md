# ADR-0008: Preserve immutable extractions and corrections

- Status: Accepted
- Date: 2026-07-13

## Context

AI providers, prompts, and model behavior change. Financial values may also be corrected by employees or finance reviewers. Overwriting the current value destroys the evidence needed to explain what happened.

## Decision

Every model attempt creates a new immutable `extraction_run`. Its predictions are stored as `extracted_fields`. Human changes create `field_corrections`; they do not mutate the original prediction.

The currently accepted value will be derived from the latest approved correction or, where policy allows, an accepted prediction.

## Consequences

- retries and model comparisons are auditable;
- debugging can reproduce the exact provider, model, prompt, and raw response;
- storage grows with each run;
- read models or views are needed to expose the current accepted state efficiently.
