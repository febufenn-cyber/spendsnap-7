import type { MiddlewareHandler } from 'hono';
import { SupabaseAuthService, type AuthService } from '../auth/supabase-auth';
import type { AppBindings, Env } from '../env';
import { AppError } from '../errors';

export type AuthServiceFactory = (env: Env) => AuthService;

function bearerToken(authorization: string | undefined): string {
  if (!authorization) {
    throw new AppError('unauthorized', 401, 'A Bearer access token is required.');
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization);
  if (!match?.[1]) {
    throw new AppError('unauthorized', 401, 'The Authorization header must use Bearer authentication.');
  }

  return match[1].trim();
}

export function authMiddleware(
  factory: AuthServiceFactory = (env) => new SupabaseAuthService(env),
): MiddlewareHandler<AppBindings> {
  return async (context, next) => {
    const token = bearerToken(context.req.header('authorization'));
    const user = await factory(context.env).verify(token);

    context.set('accessToken', token);
    context.set('user', user);
    await next();
  };
}
