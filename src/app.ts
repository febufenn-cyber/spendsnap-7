import { Hono } from 'hono';
import type { AppBindings } from './env';
import { AppError, errorMessage, isAppError } from './errors';
import { authMiddleware } from './middleware/auth';
import { requestIdMiddleware } from './middleware/request-id';
import { duplicateRoutes } from './routes/duplicates';
import { receiptRoutes } from './routes/receipts';

export function createApp(): Hono<AppBindings> {
  const app = new Hono<AppBindings>();

  app.use('*', requestIdMiddleware);

  app.get('/health', (context) => context.json({
    status: 'ok',
    service: 'spendsnap-api',
    buildSha: context.env.BUILD_SHA ?? 'unknown',
    timestamp: new Date().toISOString(),
    requestId: context.get('requestId'),
  }));

  app.use('/v1/*', authMiddleware());
  app.route('/v1/receipts', receiptRoutes);
  app.route('/v1/duplicate-candidates', duplicateRoutes);

  app.notFound((context) => context.json({
    error: {
      code: 'not_found',
      message: 'Route not found.',
      requestId: context.get('requestId'),
    },
  }, 404));

  app.onError((error, context) => {
    const requestId = context.get('requestId') || crypto.randomUUID();
    const normalized = isAppError(error)
      ? error
      : new AppError('internal_error', 500, 'An unexpected error occurred.', undefined, {
          cause: error,
        });

    console.error(JSON.stringify({
      level: 'error',
      requestId,
      code: normalized.code,
      status: normalized.status,
      message: errorMessage(error),
    }));

    return context.json({
      error: {
        code: normalized.code,
        message: normalized.message,
        ...(normalized.details ? { details: normalized.details } : {}),
        requestId,
      },
    }, normalized.status as 400 | 401 | 403 | 404 | 409 | 413 | 415 | 500 | 502);
  });

  return app;
}
