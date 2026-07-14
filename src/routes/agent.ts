import { Hono } from 'hono';
import { z } from 'zod';
import { GuardrailedAgentAdvisor } from '../agent/advisor';
import { AGENT_TASKS, redactAgentContext } from '../domain/agent';
import type { AppBindings } from '../env';
import { AppError, errorMessage, isAppError } from '../errors';
import { sha256Json, SupabaseAgentRepository } from '../repositories/supabase-agent-repository';

const uuid=z.string().uuid();
const runSchema=z.object({companyId:uuid,task:z.enum(AGENT_TASKS),entityType:z.enum(['receipt','claim','report','workflow','company']),entityId:uuid.nullable().optional()});
const confirmSchema=z.object({decision:z.enum(['accept','reject']),note:z.string().trim().max(2000).nullable().optional()});
async function jsonBody(request:Request):Promise<unknown>{if(!(request.headers.get('content-type')??'').toLowerCase().includes('application/json'))throw new AppError('bad_request',400,'The request body must be JSON.');try{return await request.json();}catch(error){throw new AppError('bad_request',400,'The JSON request body is invalid.',undefined,{cause:error});}}
function requireUuid(value:string,label:string):string{if(!uuid.safeParse(value).success)throw new AppError('bad_request',400,`${label} is invalid.`);return value;}

export const agentRoutes=new Hono<AppBindings>();
agentRoutes.post('/runs',async(context)=>{
  const parsed=runSchema.safeParse(await jsonBody(context.req.raw));if(!parsed.success)throw new AppError('bad_request',400,'Agent request is invalid.',{issues:parsed.error.issues});
  const repository=new SupabaseAgentRepository(context.env,context.get('accessToken'));
  const rawContext=await repository.context(parsed.data.companyId,parsed.data.entityType,parsed.data.entityId??null);
  const redacted=redactAgentContext(rawContext);const contextHash=await sha256Json(redacted.value);const promptVersion=context.env.AGENT_PROMPT_VERSION??'agent-v1';
  try{
    const advice=await new GuardrailedAgentAdvisor(context.env).advise(parsed.data.task,redacted.value);
    const run=await repository.recordSuccess({companyId:parsed.data.companyId,task:parsed.data.task,entityType:parsed.data.entityType,entityId:parsed.data.entityId??null,provider:advice.provider,model:advice.model,promptVersion,contextHash,context:redacted.value,warnings:redacted.warnings,raw:advice.rawResponse,proposals:advice.proposals,requestId:context.get('requestId')});
    return context.json({run,proposals:advice.proposals,advisory:true},201);
  }catch(error){
    await repository.recordFailure({companyId:parsed.data.companyId,task:parsed.data.task,entityType:parsed.data.entityType,entityId:parsed.data.entityId??null,provider:'anthropic',model:context.env.ANTHROPIC_MODEL,promptVersion,contextHash,context:redacted.value,warnings:redacted.warnings,errorCode:isAppError(error)?error.code:'internal_error',errorMessage:errorMessage(error),requestId:context.get('requestId')});
    throw error;
  }
});
agentRoutes.get('/runs',async(context)=>{const companyId=requireUuid(context.req.query('companyId')??'','Company ID');return context.json({runs:await new SupabaseAgentRepository(context.env,context.get('accessToken')).list(companyId)});});
agentRoutes.post('/proposals/:proposalId/confirm',async(context)=>{const parsed=confirmSchema.safeParse(await jsonBody(context.req.raw));if(!parsed.success)throw new AppError('bad_request',400,'Agent confirmation is invalid.',{issues:parsed.error.issues});return context.json({confirmation:await new SupabaseAgentRepository(context.env,context.get('accessToken')).confirm(requireUuid(context.req.param('proposalId'),'Proposal ID'),parsed.data.decision,parsed.data.note??null,context.get('requestId'))});});
