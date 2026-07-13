import type { FieldReviewStatus } from '../domain/confidence';
import type { ReceiptRecord, SupportedReceiptMediaType } from '../domain/receipt';

export interface Prediction<T> {
  value: T | null;
  confidence: number;
  evidence: string | null;
}

export interface LineItemPrediction {
  description: string;
  quantity: string | null;
  unitPrice: string | null;
  amount: string | null;
  confidence: number;
}

export interface ReceiptExtraction {
  documentType: Prediction<string>;
  imageQuality: Prediction<'clear' | 'usable' | 'poor' | 'unreadable'>;
  merchantName: Prediction<string>;
  invoiceNumber: Prediction<string>;
  invoiceDate: Prediction<string>;
  currency: Prediction<string>;
  subtotal: Prediction<string>;
  taxableValue: Prediction<string>;
  cgst: Prediction<string>;
  sgst: Prediction<string>;
  igst: Prediction<string>;
  otherTax: Prediction<string>;
  total: Prediction<string>;
  gstin: Prediction<string>;
  lineItems: LineItemPrediction[];
  warnings: string[];
}

export interface ExtractionInput {
  mediaType: SupportedReceiptMediaType;
  base64Data: string;
  originalFilename: string;
}

export interface ExtractorResponse {
  extraction: ReceiptExtraction;
  rawResponse: unknown;
  provider: string;
  model: string;
}

export interface ReceiptExtractor {
  extract(input: ExtractionInput): Promise<ExtractorResponse>;
}

export interface PersistedField {
  fieldName: string;
  valueJson: unknown;
  normalizedText: string | null;
  confidence: number;
  evidence: string | null;
  reviewStatus: FieldReviewStatus;
  isCritical: boolean;
  validationWarnings: string[];
}

export interface ExtractionRun {
  id: string;
  receiptId: string;
  companyId: string;
  attempt: number;
}

export interface BeginExtractionInput {
  receiptId: string;
  companyId: string;
  requestId: string;
  provider: string;
  model: string;
  promptVersion: string;
}

export interface CompleteExtractionInput {
  runId: string;
  serverSha256: string;
  actualSizeBytes: number;
  semanticFingerprint: string | null;
  rawResponse: unknown;
  fields: PersistedField[];
  needsReview: boolean;
  warnings: string[];
}

export interface ExtractionRepository {
  getReceipt(receiptId: string, companyId: string): Promise<ReceiptRecord | null>;
  begin(input: BeginExtractionInput): Promise<ExtractionRun | null>;
  complete(input: CompleteExtractionInput): Promise<void>;
  fail(runId: string, errorCode: string, errorMessage: string): Promise<void>;
}
