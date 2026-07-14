import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { AgentProposal, AgentTask } from '../domain/agent';
import type { Env } from '../env';
import { AppError } from '../errors';

function clientFor(env:Env,token:string):SupabaseClient{return createClient(env.SUPABASE_URL,env.SUPABASE_ANON_KEY,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});}
function dbError(message:string,error:{code?:string;message?:string}|null):AppError{if(error?.code==='42501')return new AppError('forbidden',403,error.message||message);if(error?.code==='P0002')return new AppError('not_found',404,error.message||message);if(['23505','23514','P0001','40001'].includes(error?.code??''))return new AppError('conflict',409,error?.message||message);return new AppError('database_error',502,message,undefined,{cause:error});}

export class SupabaseAgentRepository{
  private readonly client:SupabaseClient;
  constructor(env:Env,token:string){this.client=clientFor(env,token);}
  async context(companyId:string,entityType:string,entityId:string|null):Promise<Record<string,unknown>>{
    if(entityType==='company')return{companyId,scope:'company'};
    if(!entityId)throw new AppError('bad_request',400,'Entity ID is required for this agent task.');
    const spec:Record<string,{table:string;select:string;companyColumn:string}>={
      receipt:{table:'receipts',select:'id,company_id,status,original_filename,source,captured_at,created_at,latest_extraction_run_id,extracted_fields:extracted_fields(field_name,value_json,confidence,review_status,validation_warnings)',companyColumn:'company_id'},
      claim:{table:'expense_claims',select:'id,company_id,employee_id,receipt_id,status,merchant_name,incurred_on,currency,amount,business_purpose,notes,receipt_facts,version,category:expense_categories(id,code,name),project:expense_projects(id,code,name),costCentre:expense_cost_centres(id,code,name)',companyColumn:'company_id'},
      report:{table:'expense_reports',select:'id,company_id,employee_id,status,title,period_start,period_end,version,items:expense_report_items(position,claim:expense_claims(id,status,merchant_name,incurred_on,currency,amount,business_purpose,notes,version,category:expense_categories(code,name)))',companyColumn:'company_id'},
      workflow:{table:'approval_workflows',select:'id,company_id,report_id,submission_id,status,version,current_stage,decisions:approval_decisions(stage,action,note,created_at),policy:policy_evaluation_runs(outcome,counts,policy_set_hash,results:policy_evaluation_results(rule_code,severity,outcome,explanation,evidence)),gst:gst_readiness_evaluations(status,summary,created_at)',companyColumn:'company_id'},
    };
    const selected=spec[entityType];if(!selected)throw new AppError('bad_request',400,'Unsupported agent entity type.');
    const{data,error}=await this.client.from(selected.table).select(selected.select).eq('id',entityId).eq(selected.companyColumn,companyId).maybeSingle();
    if(error)throw dbError('Could not load agent context.',error);if(!data)throw new AppError('not_found',404,'Agent context entity not found.');
    return data as Record<string,unknown>;
  }
  async recordSuccess(input:{companyId:string;task:AgentTask;entityType:string;entityId:string|null;provider:string;model:string;promptVersion:string;contextHash:string;context:unknown;warnings:string[];raw:unknown;proposals:AgentProposal[];requestId:string}):Promise<unknown>{
    const{data,error}=await this.client.rpc('record_agent_run',{p_company_id:input.companyId,p_task:input.task,p_entity_type:input.entityType,p_entity_id:input.entityId,p_provider:input.provider,p_model:input.model,p_prompt_version:input.promptVersion,p_context_hash:input.contextHash,p_context_snapshot:input.context,p_input_warnings:input.warnings,p_raw_response:input.raw,p_proposals:input.proposals,p_request_id:input.requestId});
    if(error)throw dbError('Could not persist agent run.',error);return data;
  }
  async recordFailure(input:{companyId:string;task:AgentTask;entityType:string;entityId:string|null;provider:string;model:string;promptVersion:string;contextHash:string;context:unknown;warnings:string[];errorCode:string;errorMessage:string;requestId:string}):Promise<unknown>{
    const{data,error}=await this.client.rpc('record_failed_agent_run',{p_company_id:input.companyId,p_task:input.task,p_entity_type:input.entityType,p_entity_id:input.entityId,p_provider:input.provider,p_model:input.model,p_prompt_version:input.promptVersion,p_context_hash:input.contextHash,p_context_snapshot:input.context,p_input_warnings:input.warnings,p_error_code:input.errorCode,p_error_message:input.errorMessage,p_request_id:input.requestId});
    if(error)throw dbError('Could not persist failed agent run.',error);return data;
  }
  async list(companyId:string):Promise<Record<string,unknown>[]>{const{data,error}=await this.client.from('agent_runs').select('id,company_id,requested_by,task,entity_type,entity_id,status,provider,model,prompt_version,context_hash,input_warnings,error_code,error_message,created_at,completed_at,proposals:agent_proposals(id,proposal_type,title,rationale,proposed_payload,evidence,confidence,risk_level,status,expires_at,created_at)').eq('company_id',companyId).order('created_at',{ascending:false}).limit(100);if(error)throw dbError('Could not list agent runs.',error);return(data??[])as Record<string,unknown>[];}
  async confirm(proposalId:string,decision:'accept'|'reject',note:string|null,requestId:string):Promise<unknown>{const{data,error}=await this.client.rpc('confirm_agent_proposal',{p_proposal_id:proposalId,p_decision:decision,p_note:note,p_request_id:requestId});if(error)throw dbError('Could not confirm agent proposal.',error);return data;}
}

export async function sha256Json(value:unknown):Promise<string>{const bytes=new TextEncoder().encode(JSON.stringify(value));const digest=await crypto.subtle.digest('SHA-256',bytes);return[...new Uint8Array(digest)].map((item)=>item.toString(16).padStart(2,'0')).join('');}
