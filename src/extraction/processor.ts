import { detectImageMediaType } from '../domain/image';
import { semanticFingerprint, sha256Hex } from '../domain/fingerprint';
import { validateReceiptArithmetic } from '../domain/money';
import type { ReceiptRecord } from '../domain/receipt';
import type { Env } from '../env';
import { AppError, errorMessage, isAppError } from '../errors';
import type { ExtractionJob } from '../queue/contracts';
import { SupabaseExtractionRepository } from '../repositories/supabase-extraction-repository';
import { SupabaseStorageGateway } from '../storage/supabase-storage';
import { AnthropicReceiptExtractor } from './anthropic-extractor';
import { arrayBufferToBase64 } from './base64';
import type { ExtractionRepository, ReceiptExtractor } from './contracts';
import { mapExtractionFields } from './field-mapper';

const FINAL_STATUSES = new Set<ReceiptRecord['status']>([
  'extracted',
  'needs_review',
  'verified',
  'rejected',
  'archived',
]);

export interface ProcessingOutcome {
  status: 'processed' | 'skipped';
  receiptId: string;
  runId?: string;
  reason?: string;
}

export class ReceiptExtractionProcessor {
  private readonly repository: ExtractionRepository;
  private readonly storage: SupabaseStorageGateway;
  private readonly extractor: ReceiptExtractor;

  constructor(private readonly env: Env) {
    this.repository = new SupabaseExtractionRepository(env);
    this.storage = new SupabaseStorageGateway(env);
    this.extractor = new AnthropicReceiptExtractor(env);
  }

  async process(job: ExtractionJob): Promise<ProcessingOutcome> {
    const receipt = await this.repository.getReceipt(job.receiptId, job.companyId);
    if (!receipt) {
      throw new AppError('not_found', 404, 'The queued receipt no longer exists.');
    }

    if (FINAL_STATUSES.has(receipt.status)) {
      return {
        status: 'skipped',
        receiptId: receipt.id,
        reason: `Receipt is already in final state ${receipt.status}.`,
      };
    }

    const run = await this.repository.begin({
      receiptId: receipt.id,
      companyId: receipt.companyId,
      requestId: job.requestId,
      provider: 'anthropic',
      model: this.env.ANTHROPIC_MODEL,
      promptVersion: this.env.EXTRACTION_PROMPT_VERSION,
    });

    if (!run) {
      return {
        status: 'skipped',
        receiptId: receipt.id,
        reason: 'Another worker owns the active extraction or the receipt was already processed.',
      };
    }

    try {
      const object = await this.storage.download(receipt.storagePath);
      const maxBytes = Number.parseInt(this.env.MAX_RECEIPT_BYTES, 10) || 7_500_000;
      if (object.sizeBytes <= 0 || object.sizeBytes > maxBytes) {
        throw new AppError('payload_too_large', 413, 'The stored receipt exceeds the permitted size.');
      }

      const detectedMediaType = detectImageMediaType(object.bytes);
      if (!detectedMediaType) {
        throw new AppError('unsupported_media_type', 415, 'The stored object is not a supported receipt image.');
      }
      if (detectedMediaType !== receipt.mediaType) {
        throw new AppError('integrity_error', 400, 'The file signature does not match the declared media type.', {
          declaredMediaType: receipt.mediaType,
          detectedMediaType,
        });
      }

      const serverSha256 = await sha256Hex(object.bytes);
      const integrityWarnings: string[] = [];
      if (receipt.clientSha256 && receipt.clientSha256 !== serverSha256) {
        integrityWarnings.push('client_sha256_mismatch');
      }
      if (receipt.declaredSizeBytes !== object.sizeBytes) {
        integrityWarnings.push('declared_size_mismatch');
      }

      const response = await this.extractor.extract({
        mediaType: detectedMediaType,
        base64Data: arrayBufferToBase64(object.bytes),
        originalFilename: receipt.originalFilename,
      });

      const extraction = response.extraction;
      const arithmetic = validateReceiptArithmetic({
        subtotal: extraction.subtotal.value,
        total: extraction.total.value,
        cgst: extraction.cgst.value,
        sgst: extraction.sgst.value,
        igst: extraction.igst.value,
        otherTax: extraction.otherTax.value,
      });

      const mapped = mapExtractionFields({ extraction, arithmetic, integrityWarnings });
      const fingerprint = await semanticFingerprint({
        merchantName: extraction.merchantName.value,
        invoiceNumber: extraction.invoiceNumber.value,
        invoiceDate: extraction.invoiceDate.value,
        currency: extraction.currency.value,
        total: extraction.total.value,
      });

      await this.repository.complete({
        runId: run.id,
        serverSha256,
        actualSizeBytes: object.sizeBytes,
        semanticFingerprint: fingerprint,
        rawResponse: response.rawResponse,
        fields: mapped.fields,
        needsReview: mapped.needsReview,
        warnings: mapped.warnings,
      });

      return {
        status: 'processed',
        receiptId: receipt.id,
        runId: run.id,
      };
    } catch (error) {
      const code = isAppError(error) ? error.code : 'internal_error';
      await this.repository.fail(run.id, code, errorMessage(error));
      throw error;
    }
  }
}
