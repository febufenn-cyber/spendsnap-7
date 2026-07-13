const SCALE = 10_000n;

export const EXPENSE_CLAIM_STATUSES = ['draft', 'submitted', 'archived'] as const;
export const EXPENSE_REPORT_STATUSES = ['draft', 'submitted', 'withdrawn', 'archived'] as const;

export type ExpenseClaimStatus = (typeof EXPENSE_CLAIM_STATUSES)[number];
export type ExpenseReportStatus = (typeof EXPENSE_REPORT_STATUSES)[number];

export interface CurrencyAmount {
  currency: string;
  amount: string;
}

export interface ClaimReadinessInput {
  receiptStatus: string;
  businessPurpose: string;
  categoryActive: boolean;
  projectSelected: boolean;
  projectActive: boolean;
  costCentreSelected: boolean;
  costCentreActive: boolean;
  amount: string;
  currency: string;
  incurredOn: string;
  reportPeriodStart: string;
  reportPeriodEnd: string;
  openDuplicateCandidates: number;
}

export interface ClaimReadinessResult {
  ready: boolean;
  issues: string[];
}

export function parseDecimal4(value: string): bigint | null {
  if (!/^\d+(?:\.\d{1,4})?$/.test(value)) return null;
  const [whole = '0', fraction = ''] = value.split('.');
  return BigInt(whole) * SCALE + BigInt(fraction.padEnd(4, '0'));
}

export function formatDecimal4(value: bigint): string {
  if (value < 0n) throw new RangeError('Expense totals cannot be negative.');
  const whole = value / SCALE;
  const fraction = (value % SCALE).toString().padStart(4, '0').replace(/0+$/, '');
  return fraction.length === 0 ? whole.toString() : `${whole}.${fraction}`;
}

export function normalizeCurrency(value: string): string | null {
  const currency = value.normalize('NFKC').trim().toUpperCase();
  return /^[A-Z]{3}$/.test(currency) ? currency : null;
}

export function computeTotalsByCurrency(items: readonly CurrencyAmount[]): Record<string, string> {
  const totals = new Map<string, bigint>();
  for (const item of items) {
    const currency = normalizeCurrency(item.currency);
    const amount = parseDecimal4(item.amount);
    if (!currency) throw new RangeError(`Invalid currency: ${item.currency}`);
    if (amount == null || amount <= 0n) throw new RangeError(`Invalid positive amount: ${item.amount}`);
    totals.set(currency, (totals.get(currency) ?? 0n) + amount);
  }

  return Object.fromEntries(
    [...totals.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([currency, amount]) => [currency, formatDecimal4(amount)]),
  );
}

function validIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const timestamp = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(timestamp)) return false;
  return new Date(timestamp).toISOString().slice(0, 10) === value;
}

export function evaluateClaimReadiness(input: ClaimReadinessInput): ClaimReadinessResult {
  const issues: string[] = [];
  if (input.receiptStatus !== 'verified') issues.push('receipt_not_verified');
  if (input.businessPurpose.trim().length < 3) issues.push('business_purpose_missing');
  if (!input.categoryActive) issues.push('category_inactive');
  if (input.projectSelected && !input.projectActive) issues.push('project_inactive');
  if (input.costCentreSelected && !input.costCentreActive) issues.push('cost_centre_inactive');

  const amount = parseDecimal4(input.amount);
  if (amount == null || amount <= 0n) issues.push('amount_invalid');
  if (!normalizeCurrency(input.currency)) issues.push('currency_invalid');

  const datesValid = validIsoDate(input.incurredOn)
    && validIsoDate(input.reportPeriodStart)
    && validIsoDate(input.reportPeriodEnd)
    && input.reportPeriodStart <= input.reportPeriodEnd;
  if (!datesValid || input.incurredOn < input.reportPeriodStart || input.incurredOn > input.reportPeriodEnd) {
    issues.push('incurred_outside_report_period');
  }

  if (input.openDuplicateCandidates > 0) issues.push('duplicate_review_open');
  return { ready: issues.length === 0, issues };
}
