export interface EvaluationRecord {
  receiptId: string;
  fields: Record<string, unknown>;
}

export interface FieldMetric {
  fieldName: string;
  expected: number;
  present: number;
  matched: number;
  missing: number;
  incorrect: number;
  coverage: number;
  exactAccuracy: number;
}

export interface EvaluationReport {
  receiptCount: number;
  actualReceiptCount: number;
  missingReceipts: string[];
  extraReceipts: string[];
  fields: FieldMetric[];
  overall: {
    expected: number;
    present: number;
    matched: number;
    coverage: number;
    exactAccuracy: number;
  };
  critical: {
    expected: number;
    present: number;
    matched: number;
    coverage: number;
    exactAccuracy: number;
  };
}

const MONEY_FIELDS = new Set([
  'subtotal', 'taxable_value', 'cgst', 'sgst', 'igst', 'other_tax', 'total',
]);

const UPPERCASE_FIELDS = new Set(['currency', 'gstin', 'invoice_number']);

export const DEFAULT_CRITICAL_FIELDS = [
  'invoice_number', 'currency', 'subtotal', 'taxable_value',
  'cgst', 'sgst', 'igst', 'other_tax', 'total', 'gstin',
] as const;

function canonicalMoney(value: string): string {
  const compact = value.replace(/,/g, '').trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(compact)) return compact;
  const [whole = '0', fraction = ''] = compact.split('.');
  const normalizedWhole = whole.replace(/^(-?)0+(?=\d)/, '$1');
  const normalizedFraction = fraction.replace(/0+$/, '');
  return normalizedFraction ? `${normalizedWhole}.${normalizedFraction}` : normalizedWhole;
}

function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, stable(child)]),
    );
  }
  return value;
}

export function normalizeEvaluationValue(fieldName: string, value: unknown): string {
  if (value === null) return '__NULL__';
  if (value === undefined) return '__MISSING__';

  if (typeof value === 'string') {
    const normalized = value.normalize('NFKC').trim().replace(/\s+/g, ' ');
    if (MONEY_FIELDS.has(fieldName)) return canonicalMoney(normalized);
    if (UPPERCASE_FIELDS.has(fieldName)) return normalized.toUpperCase().replace(/\s+/g, '');
    return normalized;
  }

  if (typeof value === 'number') {
    return MONEY_FIELDS.has(fieldName) ? canonicalMoney(String(value)) : String(value);
  }

  return JSON.stringify(stable(value));
}

function ratio(numerator: number, denominator: number): number {
  return denominator === 0 ? 1 : numerator / denominator;
}

export function evaluateCorpus(
  expectedRecords: readonly EvaluationRecord[],
  actualRecords: readonly EvaluationRecord[],
  criticalFields: readonly string[] = DEFAULT_CRITICAL_FIELDS,
): EvaluationReport {
  const expectedById = new Map(expectedRecords.map((record) => [record.receiptId, record]));
  const actualById = new Map(actualRecords.map((record) => [record.receiptId, record]));
  const metricMap = new Map<string, Omit<FieldMetric, 'coverage' | 'exactAccuracy'>>();

  for (const expected of expectedRecords) {
    const actual = actualById.get(expected.receiptId);
    for (const [fieldName, expectedValue] of Object.entries(expected.fields)) {
      const metric = metricMap.get(fieldName) ?? {
        fieldName,
        expected: 0,
        present: 0,
        matched: 0,
        missing: 0,
        incorrect: 0,
      };
      metric.expected += 1;

      if (!actual || !(fieldName in actual.fields)) {
        metric.missing += 1;
      } else {
        metric.present += 1;
        const expectedNormalized = normalizeEvaluationValue(fieldName, expectedValue);
        const actualNormalized = normalizeEvaluationValue(fieldName, actual.fields[fieldName]);
        if (expectedNormalized === actualNormalized) metric.matched += 1;
        else metric.incorrect += 1;
      }
      metricMap.set(fieldName, metric);
    }
  }

  const fields = [...metricMap.values()]
    .map((metric) => ({
      ...metric,
      coverage: ratio(metric.present, metric.expected),
      exactAccuracy: ratio(metric.matched, metric.expected),
    }))
    .sort((left, right) => left.fieldName.localeCompare(right.fieldName));

  const aggregate = (selected: readonly FieldMetric[]) => {
    const expected = selected.reduce((sum, metric) => sum + metric.expected, 0);
    const present = selected.reduce((sum, metric) => sum + metric.present, 0);
    const matched = selected.reduce((sum, metric) => sum + metric.matched, 0);
    return {
      expected,
      present,
      matched,
      coverage: ratio(present, expected),
      exactAccuracy: ratio(matched, expected),
    };
  };

  const criticalSet = new Set(criticalFields);
  return {
    receiptCount: expectedRecords.length,
    actualReceiptCount: actualRecords.length,
    missingReceipts: [...expectedById.keys()].filter((id) => !actualById.has(id)).sort(),
    extraReceipts: [...actualById.keys()].filter((id) => !expectedById.has(id)).sort(),
    fields,
    overall: aggregate(fields),
    critical: aggregate(fields.filter((metric) => criticalSet.has(metric.fieldName))),
  };
}
