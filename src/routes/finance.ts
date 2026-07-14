import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseFinanceRepository } from '../repositories/supabase-finance-repository';

const uuid = z.string().uuid();
const exportSchema = z.object({ idempotencyKey: z.string().trim().min(8).max(160) });
const reconcileSchema = z.object({ note: z.string().trim().max(2000).nullable().optional() });

async function jsonBody(request: Request): Promise<unknown> {
  if (!(request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) {
    throw new AppError('bad_request', 400, 'The request body must be JSON.');
  }
  try { return await request.json(); } catch (error) {
    throw new AppError('bad_request', 400, 'The JSON request body is invalid.', undefined, { cause: error });
  }
}
function requireUuid(value: string, label: string): string {
  if (!uuid.safeParse(value).success) throw new AppError('bad_request', 400, `${label} is invalid.`);
  return value;
}

export const financeRoutes = new Hono<AppBindings>();

financeRoutes.get('/workflows', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ workflows: await repository.listWorkflows(companyId, context.req.query('status')) });
});
financeRoutes.get('/workspace', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ workspace: await repository.getWorkspace(companyId) });
});
financeRoutes.post('/workflows/:workflowId/gst-readiness', async (context) => {
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ readiness: await repository.evaluateGst(requireUuid(context.req.param('workflowId'), 'Workflow ID'), context.get('requestId')) });
});
financeRoutes.post('/workflows/:workflowId/exports', async (context) => {
  const parsed = exportSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'The export request is invalid.', { issues: parsed.error.issues });
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ export: await repository.createExport(requireUuid(context.req.param('workflowId'), 'Workflow ID'), parsed.data.idempotencyKey, context.get('requestId')) }, 201);
});
financeRoutes.get('/exports', async (context) => {
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ exports: await repository.listExports(requireUuid(context.req.query('companyId') ?? '', 'Company ID')) });
});
financeRoutes.get('/exports/:batchId', async (context) => {
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  const record = await repository.getExport(requireUuid(context.req.param('batchId'), 'Export batch ID'));
  if (!record) throw new AppError('not_found', 404, 'Export batch not found.');
  return context.json({ export: record });
});
financeRoutes.get('/exports/:batchId/download', async (context) => {
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  const record = await repository.getExport(requireUuid(context.req.param('batchId'), 'Export batch ID'));
  if (!record || typeof record.content !== 'string') throw new AppError('not_found', 404, 'Completed export content not found.');
  context.header('Content-Type', String(record.content_type ?? 'text/csv; charset=utf-8'));
  context.header('Content-Disposition', `attachment; filename="${String(record.filename).replaceAll('"', '')}"`);
  context.header('X-Content-Type-Options', 'nosniff');
  return context.body(record.content);
});
financeRoutes.post('/exports/:batchId/reconcile', async (context) => {
  const parsed = reconcileSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'The reconciliation request is invalid.', { issues: parsed.error.issues });
  const repository = new SupabaseFinanceRepository(context.env, context.get('accessToken'));
  return context.json({ export: await repository.reconcileExport(requireUuid(context.req.param('batchId'), 'Export batch ID'), parsed.data.note ?? null, context.get('requestId')) });
});
