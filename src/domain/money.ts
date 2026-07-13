const SCALE = 10_000n;

function parseDecimal(value: string): bigint | null {
  if (!/^-?\d+(?:\.\d{1,4})?$/.test(value)) return null;

  const negative = value.startsWith('-');
  const unsigned = negative ? value.slice(1) : value;
  const [whole = '0', fraction = ''] = unsigned.split('.');
  const scaled = BigInt(whole) * SCALE + BigInt(fraction.padEnd(4, '0'));
  return negative ? -scaled : scaled;
}

function difference(a: bigint, b: bigint): bigint {
  return a >= b ? a - b : b - a;
}

export interface ArithmeticInput {
  subtotal: string | null;
  total: string | null;
  cgst?: string | null;
  sgst?: string | null;
  igst?: string | null;
  otherTax?: string | null;
  tolerance?: string;
}

export interface ArithmeticResult {
  valid: boolean;
  warnings: string[];
}

export function validateReceiptArithmetic(input: ArithmeticInput): ArithmeticResult {
  const warnings: string[] = [];
  if (input.subtotal == null || input.total == null) {
    return { valid: false, warnings: ['subtotal_or_total_missing'] };
  }

  const subtotal = parseDecimal(input.subtotal);
  const total = parseDecimal(input.total);
  const tolerance = parseDecimal(input.tolerance ?? '1.00');
  if (subtotal == null || total == null || tolerance == null) {
    return { valid: false, warnings: ['invalid_decimal_format'] };
  }

  const taxValues = [input.cgst, input.sgst, input.igst, input.otherTax]
    .filter((value): value is string => value != null)
    .map(parseDecimal);

  if (taxValues.some((value) => value == null)) {
    return { valid: false, warnings: ['invalid_tax_decimal_format'] };
  }

  const calculated = taxValues.reduce<bigint>((sum, value) => sum + (value ?? 0n), subtotal);
  if (difference(calculated, total) > tolerance) {
    warnings.push('subtotal_plus_tax_does_not_match_total');
  }

  if (subtotal < 0n || total < 0n) warnings.push('negative_amount');
  return { valid: warnings.length === 0, warnings };
}
