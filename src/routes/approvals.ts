import { Hono } from 'hono';
import { z } from 'zod';
import { APPROVAL_ACTIONS, APPROVAL_STAGES } from '../domain/approval';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseApprovalRepository } from '../repositories/supabase-approval-repository';

const uuid = z.string().uuid();
const decisionSchema = z.object({
  expectedVersion: z.number().int().positive(),
  action: z.enum(APPROVAL_ACTIONS),
  note: z.string().trim().max(4000).nullable().optional(),
  claimId: uuid.nullable().optional(),
  idempotencyKey: z.string().trim().min(8).max(160),
});
const revisionSchema = z.object({ expectedVersion: z.number().int().positive() });

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

export const approvalRoutes = new Hono<AppBindings>();

approvalRoutes.get('/assignments', async (context) => {
  const stageValue = context.req.query('stage');
  const parsedStage = z.enum(APPROVAL_STAGES).safeParse(stageValue);
  if (stageValue && !parsedStage.success) throw new AppError('bad_request', 400, 'Approval stage is invalid.');
  const repository = new SupabaseApprovalRepository(context.env, context.get('accessToken'));
  return context.json({ assignments: await repository.listAssignments(parsedStage.success ? parsedStage.data : undefined) });
});

approvalRoutes.get('/workflows/:workflowId', async (context) => {
  const workflowId = requireUuid(context.req.param('workflowId'), 'Workflow ID');
  const repository = new SupabaseApprovalRepository(context.env, context.get('accessToken'));
  const workflow = await repository.getWorkflow(workflowId);
  if (!workflow) throw new AppError('not_found', 404, 'Approval workflow not found.');
  return context.json({ workflow });
});

approvalRoutes.post('/workflows/:workflowId/decisions', async (context) => {
  const workflowId = requireUuid(context.req.param('workflowId'), 'Workflow ID');
  const parsed = decisionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The approval decision is invalid.', { issues: parsed.error.issues });
  }
  if ((parsed.data.action === 'request_changes' || parsed.data.action === 'reject')
    && (parsed.data.note ?? '').trim().length < 3) {
    throw new AppError('bad_request', 400, 'A reason is required for this decision.');
  }
  const repository = new SupabaseApprovalRepository(context.env, context.get('accessToken'));
  return context.json({
    decision: await repository.decide({
      workflowId,
      expectedVersion: parsed.data.expectedVersion,
      action: parsed.data.action,
      note: parsed.data.note ?? null,
      claimId: parsed.data.claimId ?? null,
      idempotencyKey: parsed.data.idempotencyKey,
      requestId: context.get('requestId'),
    }),
  });
});

approvalRoutes.post('/workflows/:workflowId/revise', async (context) => {
  const workflowId = requireUuid(context.req.param('workflowId'), 'Workflow ID');
  const parsed = revisionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'The revision request is invalid.', { issues: parsed.error.issues });
  const repository = new SupabaseApprovalRepository(context.env, context.get('accessToken'));
  return context.json({
    revision: await repository.startRevision(workflowId, parsed.data.expectedVersion, context.get('requestId')),
  });
});

approvalRoutes.get('/notifications', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const repository = new SupabaseApprovalRepository(context.env, context.get('accessToken'));
  return context.json({ notifications: await repository.listNotifications(companyId) });
});
