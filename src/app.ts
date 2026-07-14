import { Hono } from 'hono';
import type { AppBindings } from './env';
import { AppError, errorMessage, isAppError } from './errors';
import { authMiddleware } from './middleware/auth';
import { requestIdMiddleware } from './middleware/request-id';
import { securityMiddleware } from './middleware/security';
import { adminRoutes } from './routes/admin';
import { agentRoutes } from './routes/agent';
import { approvalRoutes } from './routes/approvals';
import { billingWebhookRoutes } from './routes/billing-webhooks';
import { commercialRoutes } from './routes/commercial';
import { duplicateRoutes } from './routes/duplicates';
import { expenseRoutes } from './routes/expenses';
import { financeRoutes } from './routes/finance';
import { policyRoutes } from './routes/policies';
import { receiptRoutes } from './routes/receipts';

export function createApp(): Hono<AppBindings> {
  const app = new Hono<AppBindings>();
  app.use('*', requestIdMiddleware);
  app.use('*', securityMiddleware);

  app.get('/health', (context) => context.json({
    status: 'ok',
    service: 'spendsnap-api',
    buildSha: context.env.BUILD_SHA ?? 'unknown',
    timestamp: new Date().toISOString(),
    requestId: context.get('requestId'),
  }));

  app.get('/ready', (context) => {
    const required = [
      'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY',
      'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL', 'RECEIPT_BUCKET',
    ] as const;
    const missing = required.filter((key) => !context.env[key]);
    const optionalMissing = ['BILLING_WEBHOOK_SECRET', 'ALLOWED_ORIGINS']
      .filter((key) => !context.env[key as keyof typeof context.env]);
    return context.json({
      status: missing.length === 0 ? 'ready' : 'not_ready',
      missing,
      optionalMissing,
      buildSha: context.env.BUILD_SHA ?? 'unknown',
      requestId: context.get('requestId'),
    }, missing.length === 0 ? 200 : 503);
  });

  app.route('/webhooks', billingWebhookRoutes);

  app.use('/v1/*', authMiddleware());
  app.route('/v1/receipts', receiptRoutes);
  app.route('/v1/duplicate-candidates', duplicateRoutes);
  app.route('/v1/expenses', expenseRoutes);
  app.route('/v1/policies', policyRoutes);
  app.route('/v1/approvals', approvalRoutes);
  app.route('/v1/finance', financeRoutes);
  app.route('/v1/admin', adminRoutes);
  app.route('/v1/agent', agentRoutes);
  app.route('/v1/commercial', commercialRoutes);

  app.notFound((context) => context.json({
    error: { code: 'not_found', message: 'Route not found.', requestId: context.get('requestId') },
  }, 404));

  app.onError((error, context) => {
    const requestId = context.get('requestId') || crypto.randomUUID();
    const normalized = isAppError(error)
      ? error
      : new AppError('internal_error', 500, 'An unexpected error occurred.', undefined, { cause: error });
    console.error(JSON.stringify({
      level: 'error', requestId, code: normalized.code, status: normalized.status, message: errorMessage(error),
    }));
    return context.json({
      error: {
        code: normalized.code,
        message: normalized.message,
        ...(normalized.details ? { details: normalized.details } : {}),
        requestId,
      },
    }, normalized.status as 400 | 401 | 403 | 404 | 409 | 413 | 415 | 500 | 502 | 503);
  });

  return app;
}
