# Phase 7 — Implementation Verification

## Checkpoint

- Command: `build`
- Main head before preflight: `d7161583e28687884d6f2f98a2e782d9664726c3`
- Prior phase: Phase 6 repository complete; infrastructure/security operational gates blocked.
- Migration reserved: `202607140015_guardrailed_agent_advisor.sql`

## Outcome

Spendsnap can generate evidence-grounded, reviewable suggestions and summaries that reduce repetitive work while preserving human authority and complete audit history.

## Allowed capabilities

- suggest category;
- suggest business purpose;
- identify missing employee context;
- summarize policy exceptions;
- group likely related draft claims;
- draft reviewer reminders;
- summarize finance/GST review evidence.

## Prohibited capabilities

- approve/reject reports or exceptions;
- determine GST input-credit eligibility;
- move money or mark reimbursement paid;
- modify totals/currency/receipt evidence;
- create or override policy;
- delete evidence;
- accuse fraud;
- send external communications without confirmation.

## Architecture

- Server-only model invocation using existing Anthropic secret.
- Minimal structured context from verified facts and immutable workflow evidence; raw image bytes are excluded.
- Prompt-injection warning and text delimiters.
- Forced typed advisory output.
- Immutable run/proposal/confirmation/feedback records with provider, model, prompt version, context hash, and evidence.
- Confirmation records user intent but does not bypass existing domain APIs.

## Security and reliability

- Company membership and entity visibility checked before generation.
- Context redaction removes email, token, card-like, and secret patterns.
- Maximum context and proposal counts.
- Rate/usage metering deferred to Phase 8 but run counts are persisted.
- Provider failure creates a failed run without partial proposals.
- Advisory labels shown prominently in UI.

## Implementation slices

1. Agent evidence schema and RPCs.
2. Redaction, guardrails, typed Anthropic advisor and persistence.
3. Agent API and authenticated console.
4. Adversarial and contract tests.
5. Agent operations/evaluation runbook.

## Decision

`GO WITH LIVE MODEL EVALUATION BLOCKED`
