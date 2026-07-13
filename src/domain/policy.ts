import { parseDecimal4 } from './expense';

export const POLICY_RULE_TYPES = [
  'max_amount',
  'expense_age_days',
  'weekend_requires_note',
  'category_blocked',
  'project_required',
  'cost_centre_required',
  'gstin_required',
] as const;

export const POLICY_SEVERITIES = ['warning', 'block', 'requires_exception'] as const;
export const POLICY_EVALUATION_OUTCOMES = ['pass', 'warning', 'blocked'] as const;
export const POLICY_RESULT_OUTCOMES = ['pass', 'fail', 'not_applicable', 'waived'] as const;
export const POLICY_EXCEPTION_STATUSES = ['pending', 'approved', 'rejected', 'cancelled'] as const;

export type PolicyRuleType = (typeof POLICY_RULE_TYPES)[number];
export type PolicySeverity = (typeof POLICY_SEVERITIES)[number];
export type PolicyEvaluationOutcome = (typeof POLICY_EVALUATION_OUTCOMES)[number];
export type PolicyResultOutcome = (typeof POLICY_RESULT_OUTCOMES)[number];
export type PolicyExceptionStatus = (typeof POLICY_EXCEPTION_STATUSES)[number];

export interface PolicyRuleInput {
  id: string;
  code: string;
  version: number;
  ruleType: PolicyRuleType;
  severity: PolicySeverity;
  config: Record<string, unknown>;
}

export interface PolicyClaimInput {
  id: string;
  version: number;
  categoryId: string;
  categoryName: string;
  projectId: string | null;
  costCentreId: string | null;
  incurredOn: string;
  currency: string;
  amount: string;
  notes: string | null;
  gstin: string | null;
}

export interface ApprovedPolicyException {
  ruleId: string;
  claimId: string;
  reportVersion: number;
  claimVersion: number;
}

export interface PolicyResult {
  ruleId: string;
  ruleCode: string;
  ruleVersion: number;
  claimId: string;
  severity: PolicySeverity;
  outcome: PolicyResultOutcome;
  explanation: string;
  evidence: Record<string, unknown>;
}

export interface PolicyEvaluation {
  outcome: PolicyEvaluationOutcome;
  counts: {
    results: number;
    passed: number;
    warnings: number;
    hardBlocks: number;
    exceptionRequired: number;
    waived: number;
  };
  results: PolicyResult[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function exactKeys(config: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(config).every((key) => allowed.includes(key));
}

function optionalCategory(config: Record<string, unknown>): string | null | undefined {
  const value = config.categoryId;
  if (value === undefined || value === null) return value;
  return typeof value === 'string' && /^[0-9a-fA-F-]{36}$/.test(value) ? value : undefined;
}

export function validatePolicyRuleConfig(
  ruleType: PolicyRuleType,
  value: unknown,
): string[] {
  if (!isRecord(value)) return ['config_must_be_object'];
  const issues: string[] = [];

  if (ruleType === 'max_amount') {
    if (!exactKeys(value, ['currency', 'amount', 'categoryId'])) issues.push('unsupported_config_key');
    if (typeof value.currency !== 'string' || !/^[A-Z]{3}$/.test(value.currency)) {
      issues.push('currency_invalid');
    }
    if (typeof value.amount !== 'string') {
      issues.push('amount_invalid');
    } else {
      const amount = parseDecimal4(value.amount);
      if (amount == null || amount <= 0n) issues.push('amount_invalid');
    }
    if (value.categoryId !== undefined && optionalCategory(value) === undefined) {
      issues.push('category_id_invalid');
    }
  } else if (ruleType === 'expense_age_days') {
    if (!exactKeys(value, ['maxDays'])) issues.push('unsupported_config_key');
    if (!Number.isInteger(value.maxDays) || Number(value.maxDays) < 1 || Number(value.maxDays) > 3650) {
      issues.push('max_days_invalid');
    }
  } else if (ruleType === 'weekend_requires_note') {
    if (!exactKeys(value, ['minimumNoteLength'])) issues.push('unsupported_config_key');
    if (!Number.isInteger(value.minimumNoteLength)
      || Number(value.minimumNoteLength) < 1
      || Number(value.minimumNoteLength) > 1000) {
      issues.push('minimum_note_length_invalid');
    }
  } else {
    if (!exactKeys(value, ['categoryId'])) issues.push('unsupported_config_key');
    const category = optionalCategory(value);
    if (ruleType === 'category_blocked' && typeof category !== 'string') {
      issues.push('category_id_required');
    } else if (value.categoryId !== undefined && category === undefined) {
      issues.push('category_id_invalid');
    }
  }

  return [...new Set(issues)];
}

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed) && new Date(parsed).toISOString().slice(0, 10) === value;
}

function daysBetween(later: string, earlier: string): number {
  if (!validDate(later) || !validDate(earlier)) throw new RangeError('Policy dates must use YYYY-MM-DD.');
  return Math.floor(
    (Date.parse(`${later}T00:00:00.000Z`) - Date.parse(`${earlier}T00:00:00.000Z`)) / 86_400_000,
  );
}

function isoDayOfWeek(date: string): number {
  if (!validDate(date)) throw new RangeError('Policy dates must use YYYY-MM-DD.');
  const day = new Date(`${date}T00:00:00.000Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

function categoryFilter(rule: PolicyRuleInput): string | null {
  const value = rule.config.categoryId;
  return typeof value === 'string' ? value : null;
}

function hasMatchingException(
  exceptions: readonly ApprovedPolicyException[],
  rule: PolicyRuleInput,
  claim: PolicyClaimInput,
  reportVersion: number,
): boolean {
  return exceptions.some((exception) => exception.ruleId === rule.id
    && exception.claimId === claim.id
    && exception.reportVersion === reportVersion
    && exception.claimVersion === claim.version);
}

export interface EvaluatePolicyInput {
  reportVersion: number;
  evaluatedOn: string;
  rules: readonly PolicyRuleInput[];
  claims: readonly PolicyClaimInput[];
  approvedExceptions?: readonly ApprovedPolicyException[];
}

export function evaluatePolicy(input: EvaluatePolicyInput): PolicyEvaluation {
  if (!validDate(input.evaluatedOn)) throw new RangeError('evaluatedOn must use YYYY-MM-DD.');
  const approvedExceptions = input.approvedExceptions ?? [];
  const results: PolicyResult[] = [];

  for (const rule of [...input.rules].sort((a, b) => a.code.localeCompare(b.code) || a.version - b.version)) {
    const configIssues = validatePolicyRuleConfig(rule.ruleType, rule.config);
    if (configIssues.length > 0) {
      throw new RangeError(`Invalid configuration for policy rule ${rule.code}: ${configIssues.join(', ')}`);
    }
    const filter = categoryFilter(rule);

    for (const claim of input.claims) {
      let applies = filter == null || filter === claim.categoryId;
      let violated = false;
      let explanation = '';
      const evidence: Record<string, unknown> = {
        claimId: claim.id,
        categoryId: claim.categoryId,
        currency: claim.currency,
        amount: claim.amount,
        incurredOn: claim.incurredOn,
      };

      if (rule.ruleType === 'max_amount') {
        applies = applies && claim.currency === rule.config.currency;
        if (applies) {
          const amount = parseDecimal4(claim.amount);
          const limit = parseDecimal4(String(rule.config.amount));
          if (amount == null || limit == null) throw new RangeError('Policy amount values are invalid.');
          violated = amount > limit;
          explanation = violated
            ? `${claim.currency} ${claim.amount} exceeds the policy limit of ${rule.config.currency} ${rule.config.amount}.`
            : `${claim.currency} ${claim.amount} is within the policy limit of ${rule.config.currency} ${rule.config.amount}.`;
          evidence.limitCurrency = rule.config.currency;
          evidence.limitAmount = rule.config.amount;
        }
      } else if (rule.ruleType === 'expense_age_days') {
        if (applies) {
          const ageDays = daysBetween(input.evaluatedOn, claim.incurredOn);
          const maxDays = Number(rule.config.maxDays);
          violated = ageDays > maxDays;
          explanation = violated
            ? `Expense is ${ageDays} days old; policy allows ${maxDays} days.`
            : `Expense age of ${ageDays} days is within the ${maxDays}-day policy.`;
          evidence.ageDays = ageDays;
          evidence.maxDays = maxDays;
          evidence.evaluatedOn = input.evaluatedOn;
        }
      } else if (rule.ruleType === 'weekend_requires_note') {
        const dayOfWeek = isoDayOfWeek(claim.incurredOn);
        applies = applies && (dayOfWeek === 6 || dayOfWeek === 7);
        if (applies) {
          const noteLength = (claim.notes ?? '').trim().length;
          const minimumNoteLength = Number(rule.config.minimumNoteLength);
          violated = noteLength < minimumNoteLength;
          explanation = violated
            ? `Weekend expense requires a note of at least ${minimumNoteLength} characters.`
            : 'Weekend expense contains the required explanatory note.';
          evidence.dayOfWeek = dayOfWeek;
          evidence.noteLength = noteLength;
          evidence.minimumNoteLength = minimumNoteLength;
        }
      } else if (rule.ruleType === 'category_blocked') {
        if (applies) {
          violated = true;
          explanation = `Expense category ${claim.categoryName} is blocked by company policy.`;
        }
      } else if (rule.ruleType === 'project_required') {
        if (applies) {
          violated = claim.projectId == null;
          explanation = violated ? 'A project is required for this expense.' : 'The expense has the required project.';
          evidence.projectId = claim.projectId;
        }
      } else if (rule.ruleType === 'cost_centre_required') {
        if (applies) {
          violated = claim.costCentreId == null;
          explanation = violated
            ? 'A cost centre is required for this expense.'
            : 'The expense has the required cost centre.';
          evidence.costCentreId = claim.costCentreId;
        }
      } else if (rule.ruleType === 'gstin_required') {
        if (applies) {
          violated = !claim.gstin?.trim();
          explanation = violated
            ? 'Verified receipt facts do not contain a GSTIN.'
            : 'Verified receipt facts contain a GSTIN.';
          evidence.gstin = claim.gstin;
        }
      }

      if (!applies) continue;
      const waived = violated && rule.severity === 'requires_exception'
        && hasMatchingException(approvedExceptions, rule, claim, input.reportVersion);
      const outcome: PolicyResultOutcome = !violated ? 'pass' : waived ? 'waived' : 'fail';
      results.push({
        ruleId: rule.id,
        ruleCode: rule.code,
        ruleVersion: rule.version,
        claimId: claim.id,
        severity: rule.severity,
        outcome,
        explanation: waived
          ? `${explanation} An approved exception applies to this exact report and claim version.`
          : explanation,
        evidence,
      });
    }
  }

  const counts = {
    results: results.length,
    passed: results.filter((result) => result.outcome === 'pass').length,
    warnings: results.filter((result) => result.outcome === 'fail' && result.severity === 'warning').length,
    hardBlocks: results.filter((result) => result.outcome === 'fail' && result.severity === 'block').length,
    exceptionRequired: results.filter(
      (result) => result.outcome === 'fail' && result.severity === 'requires_exception',
    ).length,
    waived: results.filter((result) => result.outcome === 'waived').length,
  };

  const outcome: PolicyEvaluationOutcome = counts.hardBlocks + counts.exceptionRequired > 0
    ? 'blocked'
    : counts.warnings + counts.waived > 0
      ? 'warning'
      : 'pass';
  return { outcome, counts, results };
}
