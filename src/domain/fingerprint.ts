export interface SemanticFingerprintInput {
  merchantName: string | null;
  invoiceNumber: string | null;
  invoiceDate: string | null;
  currency: string | null;
  total: string | null;
}

function normalize(value: string | null): string {
  return (value ?? '')
    .normalize('NFKC')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9.-]+/g, '');
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
    normalize(input.merchantName),
    normalize(input.invoiceNumber),
    normalize(input.invoiceDate),
    normalize(input.currency),
    normalize(input.total),
  ].join('|');

  return sha256Hex(new TextEncoder().encode(canonical).buffer);
}
