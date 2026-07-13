export type FieldReviewStatus =
  | 'auto_accepted'
  | 'requires_review'
  | 'confirmed'
  | 'corrected'
  | 'rejected';

const CRITICAL_FIELDS = new Set([
  'invoice_number',
  'currency',
  'subtotal',
  'taxable_value',
  'cgst',
  'sgst',
  'igst',
  'other_tax',
  'total',
  'gstin',
]);

const CONTEXT_THRESHOLDS: Record<string, number> = {
  merchant_name: 0.97,
  invoice_date: 0.98,
  document_type: 0.95,
  image_quality: 0.95,
  line_items: 0.99,
};

export interface ReviewDecisionInput {
  fieldName: string;
  confidence: number;
  value: unknown;
  warnings?: readonly string[];
}

export interface ReviewDecision {
  isCritical: boolean;
  reviewStatus: FieldReviewStatus;
  reason: string;
}

export function decideFieldReview(input: ReviewDecisionInput): ReviewDecision {
  const isCritical = CRITICAL_FIELDS.has(input.fieldName);
  const warnings = input.warnings ?? [];

  if (isCritical) {
    return {
      isCritical: true,
      reviewStatus: 'requires_review',
      reason: input.value == null
        ? 'A financially critical field is missing.'
        : 'Financially critical fields require human confirmation.',
    };
  }

  if (input.value == null) {
    return {
      isCritical: false,
      reviewStatus: 'requires_review',
      reason: 'The field is missing.',
    };
  }

  if (warnings.length > 0) {
    return {
      isCritical: false,
      reviewStatus: 'requires_review',
      reason: 'Deterministic validation produced a warning.',
    };
  }

  const threshold = CONTEXT_THRESHOLDS[input.fieldName] ?? 0.98;
  if (!Number.isFinite(input.confidence) || input.confidence < threshold) {
    return {
      isCritical: false,
      reviewStatus: 'requires_review',
      reason: `Confidence is below the ${threshold.toFixed(2)} threshold.`,
    };
  }

  return {
    isCritical: false,
    reviewStatus: 'auto_accepted',
    reason: 'The contextual field passed its confidence threshold.',
  };
}
