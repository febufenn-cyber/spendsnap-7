# Phase 7 — Guardrailed Agentic Automation

## Delivered

- Advisory-only agent tasks for category/purpose suggestions, missing context, claim grouping, exception summaries, reviewer reminder drafts, and finance summaries.
- Server-only Anthropic invocation with a forced typed tool response.
- Minimal entity-scoped context; raw receipt image bytes are excluded.
- Email, payment-number, token, and secret redaction.
- Prompt-injection containment through explicit untrusted-context delimiters and post-generation guardrail validation.
- Immutable successful/failed run evidence with model, prompt version, context hash, warnings, raw response, proposals, confirmations, and feedback schema.
- Human accept/reject confirmation that records intent but applies no financial mutation.
- Authenticated `/agent.html` console with permanent advisory labeling.

## Apply

Apply in order:

1. `202607140015_guardrailed_agent_advisor.sql`
2. `202607140016_agent_proposal_status_fix.sql`

Set `AGENT_PROMPT_VERSION=agent-v1` and preserve the existing server-only Anthropic secret.

## Evaluation set

Before enabling for customers, build a consented, anonymized set covering:

- missing and ambiguous business purposes;
- category ambiguity;
- hostile instructions inside receipt/vendor/note text;
- policy exceptions;
- multi-currency and GST review;
- low-confidence extraction;
- conflicting evidence;
- prompts attempting approval, payment, deletion, tax advice, or fraud accusation.

Score groundedness, evidence citation, prohibited-action rate, redaction leakage, usefulness, calibration, and user acceptance. Any prohibited-action or sensitive-data leakage should block rollout.

## Operational controls

- Pin prompt version and model in every run.
- Review aggregate acceptance/rejection, but never train on customer data without explicit contractual permission.
- Disable the endpoint by removing the provider secret if safety or provider behavior regresses.
- Keep proposal count and context size bounded.
- Treat model output as untrusted until both schema and guardrail validation pass.
- Use existing domain APIs for any later accepted change; never let the agent write financial tables directly.

## External blockers

No live model request, adversarial evaluation, customer corpus test, red-team review, or console deployment was performed because provider credentials and test data were unavailable. The repository implementation is complete; rollout remains blocked until the evaluation gate passes.
