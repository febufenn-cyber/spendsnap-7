import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';

export interface SignedUpload {
  path: string;
  signedUrl: string;
  token: string | null;
}

export interface StorageGateway {
  createSignedUpload(path: string): Promise<SignedUpload>;
  assertObjectExists(path: string): Promise<void>;
}

function splitStoragePath(path: string): { folder: string; filename: string } {
  const normalized = path.replace(/^\/+|\/+$/g, '');
  const parts = normalized.split('/');
  const filename = parts.pop();
  if (!filename || parts.length < 2) {
    throw new AppError('bad_request', 400, 'The receipt storage path is invalid.');
  }

  return { folder: parts.join('/'), filename };
}

export class SupabaseStorageGateway implements StorageGateway {
  private readonly client: SupabaseClient;

  constructor(private readonly env: Env) {
    this.client = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }

  async createSignedUpload(path: string): Promise<SignedUpload> {
    const { data, error } = await this.client.storage
      .from(this.env.RECEIPT_BUCKET)
      .createSignedUploadUrl(path);

    if (error || !data?.signedUrl) {
      throw new AppError('storage_error', 502, 'Could not create a signed receipt upload URL.', undefined, {
        cause: error,
      });
    }

    return {
      path,
      signedUrl: data.signedUrl,
      token: 'token' in data && typeof data.token === 'string' ? data.token : null,
    };
  }

  async assertObjectExists(path: string): Promise<void> {
    const { folder, filename } = splitStoragePath(path);
    const { data, error } = await this.client.storage
      .from(this.env.RECEIPT_BUCKET)
      .list(folder, { limit: 10, search: filename });

    if (error) {
      throw new AppError('storage_error', 502, 'Could not verify the uploaded receipt.', undefined, {
        cause: error,
      });
    }

    if (!data?.some((object) => object.name === filename)) {
      throw new AppError('not_found', 404, 'The uploaded receipt object was not found.');
    }
  }
}
