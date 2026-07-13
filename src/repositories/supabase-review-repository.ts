import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';
import type {
  CorrectionInput,
  ReceiptReviewBundle,
  ResolutionDecision,
  ReviewRepository,
} from './review-repository';

function userClient(env: Env, accessToken: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

function databaseError(message: string, error: { code?: string; message?: string } | null): AppError {
  if (error?.code === '42501') return new AppError('forbidden', 403, message);
  if (error?.code === '23514' || error?.code === 'P0001') {
    return new AppError('conflict', 409, error.message || message);
  }
  return new AppError('database_error', 502, message, undefined, { cause: error });
}

export class SupabaseReviewRepository implements ReviewRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env, accessToken: string) {
    this.client = userClient(env, accessToken);
  }

  async getReceiptReview(receiptId: string): Promise<ReceiptReviewBundle | null> {
    const { data: receipt, error: receiptError } = await this.client
      .from('receipts')
      .select('id,company_id,submitted_by,status,original_filename,media_type,source,captured_at,created_at,latest_extraction_run_id')
      .eq('id', receiptId)
      .maybeSingle();

    if (receiptError) throw databaseError('Could not load the receipt review.', receiptError);
    if (!receipt) return null;

    const latestRunId = receipt.latest_extraction_run_id as string | null;
    const [fieldsResult, correctionsResult, resolutionsResult, duplicatesResult] = await Promise.all([
      latestRunId
        ? this.client
            .from('extracted_fields')
            .select('id,field_name,value_json,normalized_text,confidence,evidence,review_status,is_critical,validation_warnings,created_at')
            .eq('extraction_run_id', latestRunId)
            .order('field_name')
        : Promise.resolve({ data: [], error: null }),
      this.client
        .from('field_corrections')
        .select('id,field_name,previous_field_id,corrected_value,reason,status,submitted_by,reviewed_by,reviewed_at,created_at')
        .eq('receipt_id', receiptId)
        .order('created_at', { ascending: false }),
      this.client
        .from('field_resolutions')
        .select('id,field_name,source,extracted_field_id,correction_id,resolved_value,resolved_by,request_id,created_at')
        .eq('receipt_id', receiptId)
        .order('created_at', { ascending: false }),
      this.client
        .from('duplicate_candidates')
        .select('id,receipt_id,possible_duplicate_receipt_id,kind,score,reason,resolution,resolved_by,resolved_at,created_at')
        .or(`receipt_id.eq.${receiptId},possible_duplicate_receipt_id.eq.${receiptId}`)
        .order('created_at', { ascending: false }),
    ]);

    for (const result of [fieldsResult, correctionsResult, resolutionsResult, duplicatesResult]) {
      if (result.error) throw databaseError('Could not load complete receipt review data.', result.error);
    }

    return {
      receipt: receipt as Record<string, unknown>,
      fields: (fieldsResult.data ?? []) as Record<string, unknown>[],
      corrections: (correctionsResult.data ?? []) as Record<string, unknown>[],
      resolutions: (resolutionsResult.data ?? []) as Record<string, unknown>[],
      duplicateCandidates: (duplicatesResult.data ?? []) as Record<string, unknown>[],
    };
  }

  async submitCorrections(
    receiptId: string,
    userId: string,
    corrections: CorrectionInput[],
  ): Promise<Record<string, unknown>[]> {
    const { data: receipt, error: receiptError } = await this.client
      .from('receipts')
      .select('id,company_id,status')
      .eq('id', receiptId)
      .maybeSingle();

    if (receiptError) throw databaseError('Could not load the receipt.', receiptError);
    if (!receipt) throw new AppError('not_found', 404, 'Receipt not found.');

    const rows = corrections.map((correction) => ({
      receipt_id: receiptId,
      company_id: receipt.company_id,
      field_name: correction.fieldName,
      previous_field_id: correction.previousFieldId,
      corrected_value: correction.correctedValue,
      reason: correction.reason,
      status: 'pending',
      submitted_by: userId,
    }));

    const { data, error } = await this.client
      .from('field_corrections')
      .insert(rows)
      .select('id,field_name,previous_field_id,corrected_value,reason,status,submitted_by,created_at');

    if (error) throw databaseError('Could not submit receipt corrections.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async resolveFields(
    receiptId: string,
    decisions: ResolutionDecision[],
    finalize: boolean,
    requestId: string,
  ): Promise<unknown> {
    const { data, error } = await this.client.rpc('resolve_receipt_fields', {
      p_receipt_id: receiptId,
      p_decisions: decisions,
      p_finalize: finalize,
      p_request_id: requestId,
    });

    if (error) throw databaseError('Could not resolve receipt fields.', error);
    return data;
  }

  async resolveDuplicate(
    candidateId: string,
    resolution: 'confirmed_duplicate' | 'not_duplicate' | 'allowed_exception',
    note: string | null,
    requestId: string,
  ): Promise<unknown> {
    const { data, error } = await this.client.rpc('resolve_duplicate_candidate', {
      p_candidate_id: candidateId,
      p_resolution: resolution,
      p_note: note,
      p_request_id: requestId,
    });

    if (error) throw databaseError('Could not resolve the duplicate candidate.', error);
    return data;
  }
}
