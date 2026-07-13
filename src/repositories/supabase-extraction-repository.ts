import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { ReceiptRecord } from '../domain/receipt';
import type { Env } from '../env';
import { AppError } from '../errors';
import type {
  BeginExtractionInput,
  CompleteExtractionInput,
  ExtractionRepository,
  ExtractionRun,
} from '../extraction/contracts';

type ReceiptRow = {
  id: string;
  company_id: string;
  submitted_by: string;
  status: ReceiptRecord['status'];
  storage_path: string;
  original_filename: string;
  media_type: ReceiptRecord['mediaType'];
  declared_size_bytes: number;
  actual_size_bytes: number | null;
  client_sha256: string | null;
  server_sha256: string | null;
  source: ReceiptRecord['source'];
  captured_at: string | null;
  created_at: string;
  updated_at: string;
};

type BeginResult = {
  started: boolean;
  alreadyProcessed: boolean;
  runId?: string;
  attempt?: number;
};

const RECEIPT_COLUMNS = [
  'id', 'company_id', 'submitted_by', 'status', 'storage_path', 'original_filename',
  'media_type', 'declared_size_bytes', 'actual_size_bytes', 'client_sha256',
  'server_sha256', 'source', 'captured_at', 'created_at', 'updated_at',
].join(',');

function mapReceipt(row: ReceiptRow): ReceiptRecord {
  return {
    id: row.id,
    companyId: row.company_id,
    submittedBy: row.submitted_by,
    status: row.status,
    storagePath: row.storage_path,
    originalFilename: row.original_filename,
    mediaType: row.media_type,
    declaredSizeBytes: row.declared_size_bytes,
    actualSizeBytes: row.actual_size_bytes,
    clientSha256: row.client_sha256,
    serverSha256: row.server_sha256,
    source: row.source,
    capturedAt: row.captured_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class SupabaseExtractionRepository implements ExtractionRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env) {
    this.client = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }

  async getReceipt(receiptId: string, companyId: string): Promise<ReceiptRecord | null> {
    const { data, error } = await this.client
      .from('receipts')
      .select(RECEIPT_COLUMNS)
      .eq('id', receiptId)
      .eq('company_id', companyId)
      .maybeSingle<ReceiptRow>();

    if (error) {
      throw new AppError('database_error', 502, 'Could not load the queued receipt.', undefined, {
        cause: error,
      });
    }

    return data ? mapReceipt(data) : null;
  }

  async begin(input: BeginExtractionInput): Promise<ExtractionRun | null> {
    const { data, error } = await this.client.rpc('begin_receipt_extraction', {
      p_receipt_id: input.receiptId,
      p_company_id: input.companyId,
      p_provider: input.provider,
      p_model: input.model,
      p_prompt_version: input.promptVersion,
      p_request_id: input.requestId,
    });

    if (error) {
      throw new AppError('database_error', 502, 'Could not begin receipt extraction.', undefined, {
        cause: error,
      });
    }

    const result = data as BeginResult | null;
    if (!result?.started) return null;
    if (!result.runId || !result.attempt) {
      throw new AppError('database_error', 502, 'The extraction transaction returned an invalid run.');
    }

    return {
      id: result.runId,
      receiptId: input.receiptId,
      companyId: input.companyId,
      attempt: result.attempt,
    };
  }

  async complete(input: CompleteExtractionInput): Promise<void> {
    const { error } = await this.client.rpc('complete_receipt_extraction', {
      p_run_id: input.runId,
      p_server_sha256: input.serverSha256,
      p_actual_size_bytes: input.actualSizeBytes,
      p_semantic_fingerprint: input.semanticFingerprint,
      p_raw_response: input.rawResponse,
      p_fields: input.fields,
      p_needs_review: input.needsReview,
      p_warnings: input.warnings,
    });

    if (error) {
      throw new AppError('database_error', 502, 'Could not persist the completed extraction.', undefined, {
        cause: error,
      });
    }
  }

  async fail(runId: string, errorCode: string, errorMessage: string): Promise<void> {
    const { error } = await this.client.rpc('fail_receipt_extraction', {
      p_run_id: runId,
      p_error_code: errorCode,
      p_error_message: errorMessage,
    });

    if (error) {
      console.error(JSON.stringify({
        level: 'error',
        code: 'persist_extraction_failure_failed',
        runId,
        message: error.message,
      }));
    }
  }
}
