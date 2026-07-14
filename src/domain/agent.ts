export const AGENT_TASKS = [
  'suggest_category','suggest_business_purpose','missing_context','summarize_exceptions',
  'group_claims','draft_reviewer_reminder','summarize_finance_review',
] as const;
export type AgentTask = (typeof AGENT_TASKS)[number];

const prohibited = [
  /\bapprove\b.*\b(report|expense|exception)\b/i,
  /\bpay\b|\breimburse\b|\btransfer money\b/i,
  /\bdelete\b.*\b(receipt|evidence|audit)\b/i,
  /\btax credit (is|eligible|approved)\b/i,
  /\bfraud(ulent)?\b/i,
];

export function redactAgentContext(value: unknown): { value: unknown; warnings: string[] } {
  const warnings = new Set<string>();
  const visit = (item: unknown): unknown => {
    if (typeof item === 'string') {
      let text = item;
      const replacements: [RegExp,string,string][] = [
        [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[EMAIL_REDACTED]','email_redacted'],
        [/\b(?:\d[ -]*?){13,19}\b/g,'[NUMBER_REDACTED]','payment_number_redacted'],
        [/\b(?:bearer|api[_ -]?key|secret|token)\s*[:=]\s*[^\s,;]+/gi,'[SECRET_REDACTED]','secret_redacted'],
      ];
      for (const [pattern,replacement,warning] of replacements) {
        if (pattern.test(text)) { warnings.add(warning); pattern.lastIndex=0; text=text.replace(pattern,replacement); }
      }
      return text.slice(0,4000);
    }
    if (Array.isArray(item)) return item.slice(0,100).map(visit);
    if (item && typeof item === 'object') return Object.fromEntries(Object.entries(item as Record<string,unknown>).slice(0,100).map(([key,entry])=>[key,visit(entry)]));
    return item;
  };
  return { value: visit(value), warnings:[...warnings].sort() };
}

export interface AgentProposal {
  proposalType: string;
  title: string;
  rationale: string;
  payload: Record<string,unknown>;
  evidence: unknown[];
  confidence: number;
  riskLevel: 'low'|'medium'|'high';
}

export function validateAgentProposals(proposals: readonly AgentProposal[]): string[] {
  const issues:string[]=[];
  if(proposals.length>10)issues.push('too_many_proposals');
  proposals.forEach((proposal,index)=>{
    const combined=`${proposal.title} ${proposal.rationale} ${JSON.stringify(proposal.payload)}`;
    if(!/^[a-z][a-z0-9_.-]{2,79}$/.test(proposal.proposalType))issues.push(`proposal_${index}_type_invalid`);
    if(proposal.title.trim().length<1||proposal.title.length>200)issues.push(`proposal_${index}_title_invalid`);
    if(proposal.rationale.trim().length<3||proposal.rationale.length>2000)issues.push(`proposal_${index}_rationale_invalid`);
    if(!(proposal.confidence>=0&&proposal.confidence<=1))issues.push(`proposal_${index}_confidence_invalid`);
    if(prohibited.some((pattern)=>pattern.test(combined)))issues.push(`proposal_${index}_prohibited_action`);
  });
  return issues;
}
