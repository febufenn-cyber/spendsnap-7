import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';

function serviceClient(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

function databaseError(message: string, error: { code?: string; message?: string } | null): AppError {
  if (['23505', '23514', 'P0001', '40001'].includes(error?.code ?? '')) {
    return new AppError('conflict', 409, error?.message || message);
  }
  return new AppError('database_error', 502, message, undefined, { cause: error });
}

export class BillingWebhookRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env) {
    this.client = serviceClient(env);
  }

  async apply(input: {
    provider: string;
    eventId: string;
    eventType: string;
    payloadHash: string;
    payload: unknown;
  }): Promise<unknown> {
    const { data, error } = await this.client.rpc('apply_billing_event', {
      p_provider: input.provider,
      p_provider_event_id: input.eventId,
      p_event_type: input.eventType,
      p_payload_hash: input.payloadHash,
      p_payload: input.payload,
    });
    if (error) throw databaseError('Could not apply billing event.', error);
    return data;
  }
}
