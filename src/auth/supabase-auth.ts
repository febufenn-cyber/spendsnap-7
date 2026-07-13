import { createClient } from '@supabase/supabase-js';
import type { AuthenticatedUser, Env } from '../env';
import { AppError } from '../errors';

export interface AuthService {
  verify(accessToken: string): Promise<AuthenticatedUser>;
}

export class SupabaseAuthService implements AuthService {
  constructor(private readonly env: Env) {}

  async verify(accessToken: string): Promise<AuthenticatedUser> {
    const client = createClient(this.env.SUPABASE_URL, this.env.SUPABASE_ANON_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) {
      throw new AppError('unauthorized', 401, 'The access token is invalid or expired.');
    }

    return {
      id: data.user.id,
      email: data.user.email ?? null,
    };
  }
}
