import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '../env';

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{8,128}$/;

export const requestIdMiddleware: MiddlewareHandler<AppBindings> = async (context, next) => {
  const supplied = context.req.header('x-request-id');
  const requestId = supplied && REQUEST_ID_PATTERN.test(supplied)
    ? supplied
    : crypto.randomUUID();

  context.set('requestId', requestId);
  context.header('x-request-id', requestId);
  await next();
};
