import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseCommercialRepository } from '../repositories/commercial-repository';

const uuid = z.string().uuid();
const productEvents = z.enum([
  'onboarding_started','onboarding_step_completed','receipt_upload_started','receipt_verified',
  'claim_created','report_submitted','approval_completed','export_created','agent_proposal_accepted',
  'pricing_viewed','trial_started','subscription_changed',
]);

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

export const commercialRoutes = new Hono<AppBindings>();

commercialRoutes.get('/plans', async (context) => {
  const repository = new SupabaseCommercialRepository(context.env, context.get('accessToken'));
  return context.json({ plans: await repository.plans(), pricingStatus: 'hypothesis' });
});

commercialRoutes.get('/account', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const repository = new SupabaseCommercialRepository(context.env, context.get('accessToken'));
  return context.json({ account: await repository.account(companyId) });
});

commercialRoutes.post('/onboarding/:stepCode/complete', async (context) => {
  const parsed = z.object({ companyId: uuid, evidence: z.record(z.string(), z.unknown()).default({}) })
    .safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'Onboarding completion is invalid.', { issues: parsed.error.issues });
  const stepCode = context.req.param('stepCode');
  if (!/^[a-z][a-z0-9_]{1,79}$/.test(stepCode)) throw new AppError('bad_request', 400, 'Onboarding step code is invalid.');
  const repository = new SupabaseCommercialRepository(context.env, context.get('accessToken'));
  return context.json({ step: await repository.completeStep(parsed.data.companyId, stepCode, parsed.data.evidence, context.get('requestId')) });
});

commercialRoutes.post('/subscriptions/select', async (context) => {
  const parsed = z.object({ companyId: uuid, planCode: z.string().regex(/^[a-z][a-z0-9_-]{1,39}$/), expectedVersion: z.number().int().positive() })
    .safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'Plan selection is invalid.', { issues: parsed.error.issues });
  const repository = new SupabaseCommercialRepository(context.env, context.get('accessToken'));
  return context.json({ subscription: await repository.selectPlan(parsed.data.companyId, parsed.data.planCode, parsed.data.expectedVersion, context.get('requestId')) });
});

commercialRoutes.post('/events', async (context) => {
  const parsed = z.object({
    companyId: uuid.nullable().optional(),
    sessionId: z.string().trim().min(8).max(160),
    eventName: productEvents,
    properties: z.record(z.string(), z.unknown()).default({}),
  }).safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) throw new AppError('bad_request', 400, 'Product event is invalid.', { issues: parsed.error.issues });
  const serialized = JSON.stringify(parsed.data.properties);
  if (serialized.length > 10_000) throw new AppError('payload_too_large', 413, 'Product-event properties are too large.');
  const repository = new SupabaseCommercialRepository(context.env, context.get('accessToken'));
  return context.json({ eventId: await repository.recordEvent(parsed.data.companyId ?? null, parsed.data.sessionId, parsed.data.eventName, parsed.data.properties) }, 201);
});
