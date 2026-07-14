import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseAdminRepository } from '../repositories/supabase-admin-repository';

const uuid = z.string().uuid();
const roles = z.enum(['employee','manager','finance','admin','auditor']);
async function jsonBody(request: Request): Promise<unknown> {
  if (!(request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) throw new AppError('bad_request',400,'The request body must be JSON.');
  try { return await request.json(); } catch (error) { throw new AppError('bad_request',400,'The JSON request body is invalid.',undefined,{ cause:error }); }
}
function requireUuid(value: string, label: string): string { if (!uuid.safeParse(value).success) throw new AppError('bad_request',400,`${label} is invalid.`); return value; }

export const adminRoutes = new Hono<AppBindings>();
adminRoutes.get('/overview', async (context) => {
  const companyId=requireUuid(context.req.query('companyId') ?? '','Company ID');
  return context.json({ overview: await new SupabaseAdminRepository(context.env,context.get('accessToken')).getOverview(companyId) });
});
adminRoutes.patch('/security-settings', async (context) => {
  const parsed=z.object({companyId:uuid,expectedVersion:z.number().int().positive(),patch:z.object({allowedEmailDomains:z.array(z.string().trim().min(3)).max(50).optional(),receiptRetentionDays:z.number().int().min(30).max(3650).optional(),auditRetentionDays:z.number().int().min(365).max(7300).optional(),requireVerifiedEmail:z.boolean().optional(),supportAccessEnabled:z.boolean().optional()}).refine((v)=>Object.keys(v).length>0)}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success) throw new AppError('bad_request',400,'Security settings update is invalid.',{issues:parsed.error.issues});
  return context.json({ settings: await new SupabaseAdminRepository(context.env,context.get('accessToken')).updateSecuritySettings(parsed.data.companyId,parsed.data.expectedVersion,parsed.data.patch,context.get('requestId')) });
});
adminRoutes.post('/invitations', async (context) => {
  const parsed=z.object({companyId:uuid,email:z.string().email(),role:roles,expiresHours:z.number().int().min(1).max(336).default(72)}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success) throw new AppError('bad_request',400,'Invitation is invalid.',{issues:parsed.error.issues});
  return context.json({ invitation: await new SupabaseAdminRepository(context.env,context.get('accessToken')).invite(parsed.data.companyId,parsed.data.email,parsed.data.role,parsed.data.expiresHours,context.get('requestId')) },201);
});
adminRoutes.post('/invitations/accept', async (context) => {
  const parsed=z.object({token:z.string().min(32).max(256)}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success) throw new AppError('bad_request',400,'Invitation token is invalid.');
  return context.json({ membership: await new SupabaseAdminRepository(context.env,context.get('accessToken')).acceptInvitation(parsed.data.token,context.get('requestId')) });
});
adminRoutes.patch('/members/:userId', async (context) => {
  const parsed=z.object({companyId:uuid,role:roles,active:z.boolean()}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success) throw new AppError('bad_request',400,'Membership change is invalid.',{issues:parsed.error.issues});
  return context.json({ membership: await new SupabaseAdminRepository(context.env,context.get('accessToken')).changeMember(parsed.data.companyId,requireUuid(context.req.param('userId'),'User ID'),parsed.data.role,parsed.data.active,context.get('requestId')) });
});
adminRoutes.post('/deletion-requests', async (context) => {
  const parsed=z.object({companyId:uuid,scope:z.enum(['user','company','receipt']),subjectUserId:uuid.nullable().optional(),receiptId:uuid.nullable().optional(),reason:z.string().trim().min(10).max(2000)}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success) throw new AppError('bad_request',400,'Deletion request is invalid.',{issues:parsed.error.issues});
  return context.json({ request: await new SupabaseAdminRepository(context.env,context.get('accessToken')).requestDeletion(parsed.data.companyId,parsed.data.scope,parsed.data.subjectUserId ?? null,parsed.data.receiptId ?? null,parsed.data.reason,context.get('requestId')) },201);
});
adminRoutes.post('/audit-exports', async (context) => {
  const parsed=z.object({companyId:uuid,periodStart:z.string().datetime({offset:true}),periodEnd:z.string().datetime({offset:true})}).safeParse(await jsonBody(context.req.raw));
  if(!parsed.success || (parsed.success && parsed.data.periodEnd<=parsed.data.periodStart)) throw new AppError('bad_request',400,'Audit export period is invalid.');
  return context.json({ export: await new SupabaseAdminRepository(context.env,context.get('accessToken')).createAuditExport(parsed.data.companyId,parsed.data.periodStart,parsed.data.periodEnd,context.get('requestId')) },201);
});
