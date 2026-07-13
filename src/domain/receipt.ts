export const RECEIPT_STATUSES = [
  'upload_pending',
  'received',
  'queued',
  'extracting',
  'extracted',
  'needs_review',
  'verified',
  'failed',
  'rejected',
  'archived',
] as const;

export type ReceiptStatus = (typeof RECEIPT_STATUSES)[number];

export const RECEIPT_SOURCES = [
  'camera',
  'gallery',
  'email',
  'slack',
  'whatsapp',
  'bulk_upload',
] as const;

export type ReceiptSource = (typeof RECEIPT_SOURCES)[number];

export const SUPPORTED_RECEIPT_MEDIA_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
] as const;

export type SupportedReceiptMediaType = (typeof SUPPORTED_RECEIPT_MEDIA_TYPES)[number];

export interface ReceiptRecord {
  id: string;
  companyId: string;
  submittedBy: string;
  status: ReceiptStatus;
  storagePath: string;
  originalFilename: string;
  mediaType: SupportedReceiptMediaType;
  declaredSizeBytes: number;
  actualSizeBytes: number | null;
  clientSha256: string | null;
  serverSha256: string | null;
  source: ReceiptSource;
  capturedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateReceiptInput {
  id: string;
  companyId: string;
  submittedBy: string;
  storagePath: string;
  originalFilename: string;
  mediaType: SupportedReceiptMediaType;
  declaredSizeBytes: number;
  source: ReceiptSource;
  capturedAt: string | null;
}
