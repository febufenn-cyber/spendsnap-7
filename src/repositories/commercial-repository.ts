import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';

function userClient(env:Env,token:string):SupabaseClient{return createClient(env.SUPABASE_URL,env.SUPABASE_ANON_KEY,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});}
function serviceClient(env:Env):SupabaseClient{return createClient(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});}
function dbError(message:string,error:{code?:string;message?:string}|null):AppError{if(error?.code==='42501')return new AppError('forbidden',403,error.message||message);if(error?.code==='P0002')return new AppError('not_found',404,error.message||message);if(['23505','23514','P0001','40001'].includes(error?.code??''))return new AppError('conflict',409,error?.message||message);return new AppError('database_error',502,message,undefined,{cause:error});}

export class SupabaseCommercialRepository{
  private readonly user:SupabaseClient;
  constructor(private readonly env:Env,token:string){this.user=userClient(env,token);}
  async plans():Promise<Record<string,unknown>[]>{const{data,error}=await this.user.from('product_plans').select('*').eq('active',true).eq('public',true).order('monthly_price_minor');if(error)throw dbError('Could not list plans.',error);return(data??[])as Record<string,unknown>[];}
  async account(companyId:string):Promise<Record<string,unknown>>{
    const[subscription,onboarding,usage,events]=await Promise.all([
      this.user.from('company_subscriptions').select('*,plan:product_plans(*)').eq('company_id',companyId).order('created_at',{ascending:false}).limit(1).maybeSingle(),
      this.user.from('company_onboarding_steps').select('*').eq('company_id',companyId).order('step_code'),
      this.user.from('usage_events').select('metric,quantity,occurred_at').eq('company_id',companyId).gte('occurred_at',new Date(Date.now()-31*86400000).toISOString()),
      this.user.from('product_events').select('event_name,occurred_at,properties').eq('company_id',companyId).order('occurred_at',{ascending:false}).limit(50),
    ]);
    for(const result of[subscription,onboarding,usage,events])if(result.error)throw dbError('Could not load commercial account.',result.error);
    const totals:Record<string,number>={};for(const row of usage.data??[])totals[String(row.metric)]=(totals[String(row.metric)]??0)+Number(row.quantity);
    return{subscription:subscription.data,onboarding:onboarding.data??[],usageLast31Days:totals,recentEvents:events.data??[]};
  }
  private async rpc(name:string,args:Record<string,unknown>,message:string):Promise<unknown>{const{data,error}=await this.user.rpc(name,args);if(error)throw dbError(message,error);return data;}
  completeStep(companyId:string,stepCode:string,evidence:unknown,requestId:string){return this.rpc('complete_onboarding_step',{p_company_id:companyId,p_step_code:stepCode,p_evidence:evidence,p_request_id:requestId},'Could not complete onboarding step.');}
  selectPlan(companyId:string,planCode:string,expectedVersion:number,requestId:string){return this.rpc('select_subscription_plan',{p_company_id:companyId,p_plan_code:planCode,p_expected_version:expectedVersion,p_request_id:requestId},'Could not select plan.');}
  recordEvent(companyId:string|null,sessionId:string,eventName:string,properties:unknown){return this.rpc('record_product_event',{p_company_id:companyId,p_session_id:sessionId,p_event_name:eventName,p_properties:properties},'Could not record product event.');}
  async applyBillingEvent(provider:string,eventId:string,eventType:string,payloadHash:string,payload:unknown):Promise<unknown>{const{data,error}=await serviceClient(this.env).rpc('apply_billing_event',{p_provider:provider,p_provider_event_id:eventId,p_event_type:eventType,p_payload_hash:payloadHash,p_payload:payload});if(error)throw dbError('Could not apply billing event.',error);return data;}
}
