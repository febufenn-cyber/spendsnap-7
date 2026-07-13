import type { ExtractionJob } from './queue/contracts';

export interface Env {
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  ANTHROPIC_API_KEY: string;
  ANTHROPIC_MODEL: string;
  RECEIPT_BUCKET: string;
  MAX_RECEIPT_BYTES: string;
  UPLOAD_URL_TTL_SECONDS: string;
  EXTRACTION_PROMPT_VERSION: string;
  BUILD_SHA?: string;
  EXTRACTION_QUEUE: Queue<ExtractionJob>;
}

export interface AuthenticatedUser {
  id: string;
  email: string | null;
}

export interface AppVariables {
  requestId: string;
  accessToken: string;
  user: AuthenticatedUser;
}

export interface AppBindings {
  Bindings: Env;
  Variables: AppVariables;
}

export function positiveInteger(value: string, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
