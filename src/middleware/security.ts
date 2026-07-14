import { createMiddleware } from 'hono/factory';
import type { AppBindings } from '../env';
import { positiveInteger } from '../env';
import { AppError } from '../errors';

function allowedOrigins(value: string | undefined): Set<string> {
  return new Set((value ?? '').split(',').map((item) => item.trim()).filter(Boolean));
}

export const securityMiddleware = createMiddleware<AppBindings>(async (context, next) => {
  const origin = context.req.header('Origin');
  const allowed = allowedOrigins(context.env.ALLOWED_ORIGINS);
  if (origin && allowed.size > 0 && !allowed.has(origin)) {
    throw new AppError('forbidden', 403, 'Request origin is not allowed.');
  }
  if (context.req.method === 'OPTIONS') {
    if (origin && (allowed.size === 0 || allowed.has(origin))) {
      context.header('Access-Control-Allow-Origin', origin);
      context.header('Access-Control-Allow-Credentials', 'true');
      context.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Request-ID, Idempotency-Key');
      context.header('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
      context.header('Vary', 'Origin');
    }
    return context.body(null, 204);
  }
  const contentLength = Number.parseInt(context.req.header('Content-Length') ?? '0', 10);
  const maxJsonBytes = positiveInteger(context.env.MAX_JSON_BYTES, 1_000_000);
  if (Number.isFinite(contentLength) && contentLength > maxJsonBytes
    && (context.req.header('Content-Type') ?? '').includes('application/json')) {
    throw new AppError('payload_too_large', 413, `JSON requests must not exceed ${maxJsonBytes} bytes.`);
  }
  await next();
  context.header('X-Content-Type-Options', 'nosniff');
  context.header('X-Frame-Options', 'DENY');
  context.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  context.header('Permissions-Policy', 'camera=(self), microphone=(), geolocation=()');
  context.header('Cross-Origin-Resource-Policy', 'same-site');
  context.header('Cache-Control', context.req.path.startsWith('/v1/') ? 'no-store' : 'no-cache');
  if (origin && (allowed.size === 0 || allowed.has(origin))) {
    context.header('Access-Control-Allow-Origin', origin);
    context.header('Access-Control-Allow-Credentials', 'true');
    context.header('Vary', 'Origin');
  }
});
