import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';
import type { CreateReceiptInput, ReceiptRecord } from '../domain/receipt';
import type {
  CompleteReceiptInput,
  ReceiptRepository,
  ServiceReceiptRepository,
} from './receipt-repository';

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

const RECEIPT_COLUMNS = [
  'id',
  'company_id',
  'submitted_by',
  'status',
  'storage_path',
  'original_filename',
  'media_type',
  'declared_size_bytes',
  'actual_size_bytes',
  'client_sha256',
  'server_sha256',
  'source',
  'captured_at',
  'created_at',
  'updated_at',
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

function userClient(env: Env, accessToken: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

function serviceClient(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

export class SupabaseReceiptRepository implements ReceiptRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env, accessToken: string) {
    this.client = userClient(env, accessToken);
  }

  async create(input: CreateReceiptInput): Promise<ReceiptRecord> {
    const { data, error } = await this.client
      .from('receipts')
      .insert({
        id: input.id,
        company_id: input.companyId,
        submitted_by: input.submittedBy,
        status: 'upload_pending',
        storage_path: input.storagePath,
        original_filename: input.originalFilename,
        media_type: input.mediaType,
        declared_size_bytes: input.declaredSizeBytes,
        source: input.source,
        captured_at: input.capturedAt,
      })
      .select(RECEIPT_COLUMNS)
      .single<ReceiptRow>();

    if (error || !data) {
      throw new AppError('database_error', 502, 'Could not create the receipt record.', undefined, {
        cause: error,
      });
    }

    return mapReceipt(data);
  }

  async getById(receiptId: string): Promise<ReceiptRecord | null> {
    const { data, error } = await this.client
      .from('receipts')
      .select(RECEIPT_COLUMNS)
      .eq('id', receiptId)
      .maybeSingle<ReceiptRow>();

    if (error) {
      throw new AppError('database_error', 502, 'Could not load the receipt.', undefined, {
        cause: error,
      });
    }

    return data ? mapReceipt(data) : null;
  }
}

export class SupabaseServiceReceiptRepository implements ServiceReceiptRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env) {
    this.client = serviceClient(env);
  }

  async markReceived(receiptId: string, input: CompleteReceiptInput): Promise<ReceiptRecord> {
    return this.updateStatus(receiptId, ['upload_pending', 'received'], 'received', {
      client_sha256: input.clientSha256,
      upload_completed_at: new Date().toISOString(),
    });
  }

  async markQueued(receiptId: string): Promise<ReceiptRecord> {
    return this.updateStatus(receiptId, ['received', 'queued'], 'queued', {
      extraction_queued_at: new Date().toISOString(),
    });
  }

  private async updateStatus(
    receiptId: string,
    allowedStatuses: ReceiptRecord['status'][],
    nextStatus: ReceiptRecord['status'],
    extra: Record<string, unknown>,
  ): Promise<ReceiptRecord> {
    const { data, error } = await this.client
      .from('receipts')
      .update({ status: nextStatus, ...extra })
      .eq('id', receiptId)
      .in('status', allowedStatuses)
      .select(RECEIPT_COLUMNS)
      .maybeSingle<ReceiptRow>();

    if (error) {
      throw new AppError('database_error', 502, 'Could not update the receipt state.', undefined, {
        cause: error,
      });
    }

    if (!data) {
      throw new AppError('conflict', 409, 'The receipt is not in a state that permits this operation.');
    }

    return mapReceipt(data);
  }
}
