# ADR-0011 — Deterministic, versioned policy engine

## Status

Accepted for Phase 3.

## Context

Expense policy affects whether an employee may submit a financial claim. Free-form AI interpretation, mutable rules, client-computed results, or reusable stale exceptions would make decisions difficult to reproduce and audit.

## Decision

Spendsnap will:

- implement a fixed set of typed deterministic rule kinds;
- validate every rule configuration in both API and database layers;
- create new immutable rule versions rather than rewriting historical rules;
- persist append-only evaluation runs and results;
- evaluate current effective rules again inside report submission;
- serialize company policy mutation and evaluation with transaction advisory locks;
- support explicit exceptions only for rules marked `requires_exception`;
- bind approved exceptions to report, claim, and rule versions;
- embed the exact evaluation snapshot in the immutable report submission.

The evaluator will never execute arbitrary user expressions, model-generated code, SQL fragments, or JavaScript.

## Consequences

### Positive

- decisions are reproducible and explainable;
- historical reports retain the policy facts used at submission;
- stale previews and stale exceptions cannot authorize a changed report;
- policy administration remains auditable;
- security boundaries are enforceable in PostgreSQL.

### Negative

- the initial rule catalog is intentionally limited;
- new rule types require reviewed code and migrations;
- policy-document ingestion must remain advisory until a human approves typed rules;
- complex enterprise policies may require later rule composition.

## Rejected alternatives

### AI-only policy interpretation

Rejected because identical claims could receive inconsistent decisions and explanations would not be reliably reproducible.

### Mutable policy rows

Rejected because editing a rule would rewrite the meaning of historical evaluations.

### Client-side evaluation

Rejected because clients could bypass, alter, or submit stale results.

### Generic expression language in Phase 3

Rejected because it substantially expands injection, authorization, testing, and operational risk before real policy patterns are known.
