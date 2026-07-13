import { decideFieldReview } from '../domain/confidence';
import type { ArithmeticResult } from '../domain/money';
import type { PersistedField, Prediction, ReceiptExtraction } from './contracts';

interface FieldDefinition {
  fieldName: string;
  prediction: Prediction<unknown>;
  warnings?: string[];
}

function normalizedText(value: unknown): string | null {
  if (typeof value === 'string') return value.normalize('NFKC').trim() || null;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return null;
}

function averageConfidence(values: readonly number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function field(definition: FieldDefinition): PersistedField {
  const warnings = definition.warnings ?? [];
  const decision = decideFieldReview({
    fieldName: definition.fieldName,
    confidence: definition.prediction.confidence,
    value: definition.prediction.value,
    warnings,
  });

  return {
    fieldName: definition.fieldName,
    valueJson: definition.prediction.value,
    normalizedText: normalizedText(definition.prediction.value),
    confidence: definition.prediction.confidence,
    evidence: definition.prediction.evidence,
    reviewStatus: decision.reviewStatus,
    isCritical: decision.isCritical,
    validationWarnings: warnings,
  };
}

export interface MapExtractionInput {
  extraction: ReceiptExtraction;
  arithmetic: ArithmeticResult;
  integrityWarnings: string[];
}

export interface MappedExtraction {
  fields: PersistedField[];
  needsReview: boolean;
  warnings: string[];
}

export function mapExtractionFields(input: MapExtractionInput): MappedExtraction {
  const amountWarnings = input.arithmetic.warnings;
  const definitions: FieldDefinition[] = [
    { fieldName: 'document_type', prediction: input.extraction.documentType },
    { fieldName: 'image_quality', prediction: input.extraction.imageQuality },
    { fieldName: 'merchant_name', prediction: input.extraction.merchantName },
    { fieldName: 'invoice_number', prediction: input.extraction.invoiceNumber },
    { fieldName: 'invoice_date', prediction: input.extraction.invoiceDate },
    { fieldName: 'currency', prediction: input.extraction.currency },
    { fieldName: 'subtotal', prediction: input.extraction.subtotal, warnings: amountWarnings },
    { fieldName: 'taxable_value', prediction: input.extraction.taxableValue },
    { fieldName: 'cgst', prediction: input.extraction.cgst, warnings: amountWarnings },
    { fieldName: 'sgst', prediction: input.extraction.sgst, warnings: amountWarnings },
    { fieldName: 'igst', prediction: input.extraction.igst, warnings: amountWarnings },
    { fieldName: 'other_tax', prediction: input.extraction.otherTax, warnings: amountWarnings },
    { fieldName: 'total', prediction: input.extraction.total, warnings: amountWarnings },
    { fieldName: 'gstin', prediction: input.extraction.gstin },
  ];

  const fields = definitions.map(field);
  const lineItemConfidence = averageConfidence(input.extraction.lineItems.map((item) => item.confidence));
  fields.push(field({
    fieldName: 'line_items',
    prediction: {
      value: input.extraction.lineItems,
      confidence: lineItemConfidence,
      evidence: null,
    },
  }));

  const combinedWarnings = [
    ...new Set([
      ...input.extraction.warnings,
      ...input.arithmetic.warnings,
      ...input.integrityWarnings,
    ]),
  ];

  fields.push(field({
    fieldName: 'document_integrity',
    prediction: {
      value: { warnings: input.integrityWarnings },
      confidence: input.integrityWarnings.length === 0 ? 1 : 0,
      evidence: null,
    },
    warnings: input.integrityWarnings,
  }));

  fields.push(field({
    fieldName: 'model_warnings',
    prediction: {
      value: input.extraction.warnings,
      confidence: input.extraction.warnings.length === 0 ? 1 : 0,
      evidence: null,
    },
    warnings: input.extraction.warnings,
  }));

  return {
    fields,
    needsReview: fields.some((item) => item.reviewStatus === 'requires_review'),
    warnings: combinedWarnings,
  };
}
