import type { SupportedReceiptMediaType } from './receipt';

export function detectImageMediaType(bytes: ArrayBuffer): SupportedReceiptMediaType | null {
  const view = new Uint8Array(bytes);

  if (view.length >= 3 && view[0] === 0xff && view[1] === 0xd8 && view[2] === 0xff) {
    return 'image/jpeg';
  }

  if (
    view.length >= 8
    && view[0] === 0x89
    && view[1] === 0x50
    && view[2] === 0x4e
    && view[3] === 0x47
    && view[4] === 0x0d
    && view[5] === 0x0a
    && view[6] === 0x1a
    && view[7] === 0x0a
  ) {
    return 'image/png';
  }

  if (
    view.length >= 12
    && String.fromCharCode(...view.subarray(0, 4)) === 'RIFF'
    && String.fromCharCode(...view.subarray(8, 12)) === 'WEBP'
  ) {
    return 'image/webp';
  }

  return null;
}
