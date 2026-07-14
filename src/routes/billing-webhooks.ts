import { Hono } from 'hono';
import { sha256Text, verifyBillingSignature } from '../domain/billing';
import type { AppBindings } from '../env';
import { positiveInteger } from '../env';
import { AppError } from '../errors';
import { BillingWebhookRepository } from '../repositories/billing-webhook-repository';

function requiredHeader(request: Request, name: string, pattern: RegExp, maximum: number): string {
  const value = request.headers.get(name)?.trim() ?? '';
  if (!value || value.length > maximum || !pattern.test(value)) {
    throw new AppError('bad_request', 400, `Billing header ${name} is missing or invalid.`);
  }
  return value;
}

export const billingWebhookRoutes = new Hono<AppBindings>();

billingWebhookRoutes.post('/billing', async (context) => {
  const secret = context.env.BILLING_WEBHOOK_SECRET;
  if (!secret) throw new AppError('internal_error', 500, 'Billing webhook is not configured.');

  const contentLength = Number.parseInt(context.req.header('Content-Length') ?? '0', 10);
  const maximum = Math.min(positiveInteger(context.env.MAX_JSON_BYTES, 1_000_000), 1_000_000);
  if (Number.isFinite(contentLength) && contentLength > maximum) {
    throw new AppError('payload_too_large', 413, `Billing webhook must not exceed ${maximum} bytes.`);
  }

  const provider = requiredHeader(context.req.raw, 'X-Spendsnap-Provider', /^[a-z][a-z0-9_-]{1,39}$/, 40);
  const eventId = requiredHeader(context.req.raw, 'X-Spendsnap-Event-ID', /^[A-Za-z0-9_.:-]{8,200}$/, 200);
  const eventType = requiredHeader(context.req.raw, 'X-Spendsnap-Event-Type', /^[a-z][a-z0-9_.-]{2,119}$/, 120);
  const signature = requiredHeader(context.req.raw, 'X-Spendsnap-Signature', /^[a-f0-9]{64}$/i, 64).toLowerCase();
  const body = await context.req.text();
  if (new TextEncoder().encode(body).byteLength > maximum) {
    throw new AppError('payload_too_large', 413, `Billing webhook must not exceed ${maximum} bytes.`);
  }
  if (!(await verifyBillingSignature(body, signature, secret))) {
    throw new AppError('unauthorized', 401, 'Billing webhook signature is invalid.');
  }

  let payload: unknown;
  try { payload = JSON.parse(body); } catch (error) {
    throw new AppError('bad_request', 400, 'Billing webhook JSON is invalid.', undefined, { cause: error });
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new AppError('bad_request', 400, 'Billing webhook payload must be an object.');
  }

  const result = await new BillingWebhookRepository(context.env).apply({
    provider,
    eventId,
    eventType,
    payloadHash: await sha256Text(body),
    payload,
  });
  return context.json({ received: true, result });
});
