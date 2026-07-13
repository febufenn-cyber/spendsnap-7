export interface SemanticFingerprintInput {
  merchantName: string | null;
  invoiceNumber: string | null;
  invoiceDate: string | null;
  currency: string | null;
  total: string | null;
}

function normalizeIdentity(value: string | null): string {
  return (value ?? '')
    .normalize('NFKC')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '');
}

function normalizeAmount(value: string | null): string {
  const compact = (value ?? '').replace(/,/g, '').trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(compact)) return normalizeIdentity(value);

  const [whole = '0', fraction = ''] = compact.split('.');
  const normalizedWhole = whole.replace(/^(-?)0+(?=\d)/, '$1');
  const normalizedFraction = fraction.replace(/0+$/, '');
  return normalizedFraction ? `${normalizedWhole}.${normalizedFraction}` : normalizedWhole;
}

export async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export async function semanticFingerprint(input: SemanticFingerprintInput): Promise<string | null> {
  if (!input.total || !input.currency || (!input.invoiceNumber && !input.invoiceDate)) {
    return null;
  }

  const canonical = [
    normalizeIdentity(input.merchantName),
    normalizeIdentity(input.invoiceNumber),
    normalizeIdentity(input.invoiceDate),
    normalizeIdentity(input.currency),
    normalizeAmount(input.total),
  ].join('|');

  return sha256Hex(new TextEncoder().encode(canonical).buffer);
}
