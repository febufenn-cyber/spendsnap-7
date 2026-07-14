import { FormEvent, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { api } from './lib/api';
import { supabase } from './lib/supabase';

type Row = Record<string, unknown>;
type Workspace = { companyId: string; companyName: string; role: string };

export function FinancePortal() {
  const [session, setSession] = useState<Session | null>(null);
  const [email, setEmail] = useState('');
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [workflows, setWorkflows] = useState<Row[]>([]);
  const [exports, setExports] = useState<Row[]>([]);
  const [accounting, setAccounting] = useState<Row | null>(null);
  const [selected, setSelected] = useState<Row | null>(null);
  const [result, setResult] = useState<unknown>(null);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);
  useEffect(() => {
    if (!session) return;
    supabase.from('company_memberships').select('company_id,role,companies(id,name)').eq('active', true)
      .then(({ data, error }) => {
        if (error) return setNotice(error.message);
        const allowed = (data ?? []).filter((row) => ['finance', 'admin', 'auditor'].includes(String(row.role))).map((row) => {
          const company = row.companies as unknown as { id: string; name: string };
          return { companyId: String(row.company_id), companyName: company.name, role: String(row.role) };
        });
        setWorkspaces(allowed); setWorkspace(allowed[0] ?? null);
      });
  }, [session?.user.id]);
  async function load() {
    if (!workspace) return;
    const [workflowData, exportData, workspaceData] = await Promise.all([
      api<{ workflows: Row[] }>(`/v1/finance/workflows?companyId=${workspace.companyId}`),
      api<{ exports: Row[] }>(`/v1/finance/exports?companyId=${workspace.companyId}`),
      api<{ workspace: Row }>(`/v1/finance/workspace?companyId=${workspace.companyId}`),
    ]);
    setWorkflows(workflowData.workflows); setExports(exportData.exports); setAccounting(workspaceData.workspace);
  }
  useEffect(() => { load().catch((error) => setNotice(error.message)); }, [workspace?.companyId]);
  async function signIn(event: FormEvent) {
    event.preventDefault();
    const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: `${window.location.origin}/finance.html` } });
    setNotice(error?.message ?? 'Check your work email for the secure sign-in link.');
  }
  async function evaluate() {
    if (!selected) return;
    const payload = await api<{ readiness: unknown }>(`/v1/finance/workflows/${selected.id}/gst-readiness`, { method: 'POST' });
    setResult(payload.readiness);
  }
  async function createExport() {
    if (!selected) return;
    const payload = await api<{ export: Row }>(`/v1/finance/workflows/${selected.id}/exports`, {
      method: 'POST', body: JSON.stringify({ idempotencyKey: `${selected.id}:tally:${crypto.randomUUID()}` }),
    });
    setResult(payload.export); await load();
  }
  async function download(batchId: string, filename: string) {
    const { data: { session: current } } = await supabase.auth.getSession();
    const response = await fetch(`${import.meta.env.VITE_API_BASE_URL}/v1/finance/exports/${batchId}/download`, { headers: { Authorization: `Bearer ${current?.access_token}` } });
    if (!response.ok) throw new Error('Download failed.');
    const url = URL.createObjectURL(await response.blob());
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = filename; anchor.click(); URL.revokeObjectURL(url);
  }
  if (!session) return <main className="auth-shell"><section className="auth-card"><p className="eyebrow">Finance operations</p><h1>Spendsnap Finance</h1><p>Authenticated finance and audit access only.</p><form className="stack" onSubmit={signIn}><label>Work email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label><button className="primary">Send magic link</button></form>{notice && <p>{notice}</p>}</section></main>;
  if (!workspace) return <main className="center"><section><h1>No finance workspace</h1><p>Your account needs finance, admin or auditor membership.</p></section></main>;
  return <div className="app-shell"><aside className="sidebar"><div><div className="brand"><span className="brand-mark">S</span><span><strong>Spendsnap Finance</strong><small>GST readiness &amp; export</small></span></div><label className="workspace-label">Workspace<select value={workspace.companyId} onChange={(event) => setWorkspace(workspaces.find((item) => item.companyId === event.target.value) ?? null)}>{workspaces.map((item) => <option key={item.companyId} value={item.companyId}>{item.companyName} · {item.role}</option>)}</select></label><nav><a href="/">Employee app</a></nav></div><button className="sign-out" onClick={() => supabase.auth.signOut()}>Sign out</button></aside><main className="main"><section className="page-section"><header className="page-header"><div><p className="eyebrow">Finance review</p><h2>Accounting workspace</h2></div></header>{notice && <div className="notice error">{notice}</div>}<div className="card-grid"><article className="data-card"><strong>Ledgers</strong><p className="money">{Array.isArray(accounting?.ledgers) ? accounting.ledgers.length : 0}</p></article><article className="data-card"><strong>Category mappings</strong><p className="money">{Array.isArray(accounting?.mappings) ? accounting.mappings.length : 0}</p></article><article className="data-card"><strong>Period locks</strong><p className="money">{Array.isArray(accounting?.periodLocks) ? accounting.periodLocks.length : 0}</p></article></div><div className="split"><div><h3>Approval workflows</h3>{workflows.map((workflow) => <button className="list-button" key={String(workflow.id)} onClick={() => { setSelected(workflow); setResult(null); }}><span>Submission {String(workflow.submission_number)}</span><span>{String(workflow.status)}</span></button>)}</div><div>{selected ? <article className="detail-panel"><h3>Workflow {String(selected.id)}</h3><p>Status: <span className="status-pill">{String(selected.status)}</span></p><div className="action-row"><button onClick={evaluate}>Evaluate GST readiness</button><button className="primary" disabled={selected.status !== 'finance_approved'} onClick={createExport}>Generate Tally CSV</button></div><p className="hint">GST readiness checks document completeness only; it is not tax-credit eligibility advice.</p>{result ? <pre>{JSON.stringify(result, null, 2)}</pre> : null}</article> : <p className="empty-card">Select a workflow.</p>}</div></div><h3>Export history</h3><div className="table-wrap"><table><thead><tr><th>File</th><th>Status</th><th>Items</th><th>Checksum</th><th></th></tr></thead><tbody>{exports.map((item) => <tr key={String(item.id)}><td>{String(item.filename)}</td><td>{String(item.status)}</td><td>{String(item.item_count)}</td><td><code>{String(item.checksum_sha256 ?? '')}</code></td><td><button onClick={() => download(String(item.id), String(item.filename)).catch((error) => setNotice(error.message))}>Download</button></td></tr>)}</tbody></table></div></section></main></div>;
}
