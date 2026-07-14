export type GstReadinessStatus = 'complete' | 'review_required' | 'not_applicable';

export interface GstFacts {
  gstin?: string | null;
  invoice_number?: string | null;
  invoice_date?: string | null;
  taxable_value?: string | null;
  cgst?: string | null;
  sgst?: string | null;
  igst?: string | null;
}

export interface GstReadiness {
  status: GstReadinessStatus;
  issues: string[];
  label: string;
}

const decimal = /^\d+(?:\.\d{1,4})?$/;

function amount(value: string | null | undefined): bigint | null {
  if (value == null || value === '') return 0n;
  if (!decimal.test(value)) return null;
  const [whole, fraction = ''] = value.split('.');
  return BigInt(whole) * 10_000n + BigInt(fraction.padEnd(4, '0'));
}

export function evaluateGstReadiness(facts: GstFacts): GstReadiness {
  const issues: string[] = [];
  const cgst = amount(facts.cgst);
  const sgst = amount(facts.sgst);
  const igst = amount(facts.igst);
  if ([cgst, sgst, igst].some((value) => value == null)) {
    return {
      status: 'review_required',
      issues: ['tax_amount_format_invalid'],
      label: 'GST completeness requires tax review.',
    };
  }
  const gstin = facts.gstin?.trim() ?? '';
  const noGstEvidence = !gstin && !facts.taxable_value && cgst === 0n && sgst === 0n && igst === 0n;
  if (noGstEvidence) {
    return {
      status: 'not_applicable',
      issues: [],
      label: 'No GST fields detected; review only if a tax invoice was expected.',
    };
  }
  if (!gstin) issues.push('gstin_missing');
  else if (!/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gstin)) {
    issues.push('gstin_format_questionable');
  }
  if (!facts.invoice_number?.trim()) issues.push('invoice_number_missing');
  if (!facts.invoice_date?.trim()) issues.push('invoice_date_missing');
  if (!facts.taxable_value?.trim()) issues.push('taxable_value_missing');
  if ((igst ?? 0n) > 0n && ((cgst ?? 0n) > 0n || (sgst ?? 0n) > 0n)) {
    issues.push('igst_and_cgst_sgst_both_present');
  }
  if (((cgst ?? 0n) > 0n) !== ((sgst ?? 0n) > 0n)) issues.push('cgst_sgst_pair_incomplete');
  return issues.length === 0
    ? {
        status: 'complete',
        issues,
        label: 'GST fields appear complete; tax eligibility still requires professional review.',
      }
    : { status: 'review_required', issues, label: 'GST completeness requires tax review.' };
}

export function csvCell(value: unknown): string {
  let text = value == null ? '' : String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export interface TallyRow {
  voucherDate: string;
  voucherType: string;
  ledger: string;
  vendor: string;
  reference: string | null;
  amount: string;
  currency: string;
  costCentre: string | null;
  project: string | null;
  narration: string;
  gstin: string | null;
  taxableValue: string | null;
  cgst: string | null;
  sgst: string | null;
  igst: string | null;
  gstReadiness: GstReadinessStatus;
}

export const TALLY_HEADERS = [
  'Voucher Date', 'Voucher Type', 'Ledger', 'Vendor', 'Reference', 'Amount', 'Currency',
  'Cost Centre', 'Project', 'Narration', 'GSTIN', 'Taxable Value', 'CGST', 'SGST', 'IGST',
  'GST Readiness',
] as const;

export function tallyCsv(rows: readonly TallyRow[]): string {
  const lines = [TALLY_HEADERS.join(',')];
  for (const row of rows) {
    lines.push([
      row.voucherDate, row.voucherType, row.ledger, row.vendor, row.reference, row.amount,
      row.currency, row.costCentre, row.project, row.narration, row.gstin, row.taxableValue,
      row.cgst, row.sgst, row.igst, row.gstReadiness,
    ].map(csvCell).join(','));
  }
  return `${lines.join('\r\n')}\r\n`;
}
