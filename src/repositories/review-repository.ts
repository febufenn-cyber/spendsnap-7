export interface CorrectionInput {
  fieldName: string;
  previousFieldId: string;
  correctedValue: unknown;
  reason: string | null;
}

export interface ResolutionDecision {
  fieldName: string;
  source: 'prediction' | 'correction';
  sourceId: string;
}

export interface ReceiptReviewBundle {
  receipt: Record<string, unknown>;
  fields: Record<string, unknown>[];
  corrections: Record<string, unknown>[];
  resolutions: Record<string, unknown>[];
  duplicateCandidates: Record<string, unknown>[];
}

export interface ReviewRepository {
  getReceiptReview(receiptId: string): Promise<ReceiptReviewBundle | null>;
  submitCorrections(receiptId: string, userId: string, corrections: CorrectionInput[]): Promise<Record<string, unknown>[]>;
  resolveFields(receiptId: string, decisions: ResolutionDecision[], finalize: boolean, requestId: string): Promise<unknown>;
  resolveDuplicate(candidateId: string, resolution: 'confirmed_duplicate' | 'not_duplicate' | 'allowed_exception', note: string | null, requestId: string): Promise<unknown>;
}
