import { FormEvent, useEffect, useMemo, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { api, ApiError, sha256 } from './lib/api';
import { supabase } from './lib/supabase';

type Role = 'employee' | 'manager' | 'finance' | 'admin' | 'auditor';
type Workspace = { companyId: string; companyName: string; role: Role };
type Notice = { kind: 'success' | 'error' | 'info'; message: string } | null;
type Tab = 'receipts' | 'claims' | 'reports' | 'reviews' | 'policies';

type UnknownRow = Record<string, unknown>;

function NoticeBar({ notice }: { notice: Notice }) {
  if (!notice) return null;
  return <div className={`notice ${notice.kind}`} role={notice.kind === 'error' ? 'alert' : 'status'}>{notice.message}</div>;
}

function Login({ onNotice }: { onNotice: (notice: Notice) => void }) {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true);
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    });
    setBusy(false);
    onNotice(error
      ? { kind: 'error', message: error.message }
      : { kind: 'success', message: 'Check your email for the secure sign-in link.' });
  }
  return <main className="auth-shell">
    <section className="auth-card" aria-labelledby="login-title">
      <div className="brand-mark" aria-hidden="true">S</div>
      <p className="eyebrow">Verified expense operations</p>
      <h1 id="login-title">Sign in to Spendsnap</h1>
      <p>Use your work email. Approval links never bypass authentication.</p>
      <form onSubmit={submit} className="stack">
        <label>Email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" /></label>
        <button className="primary" disabled={busy}>{busy ? 'Sending…' : 'Send magic link'}</button>
      </form>
    </section>
  </main>;
}

function ReceiptScreen({ workspace, onNotice }: { workspace: Workspace; onNotice: (notice: Notice) => void }) {
  const [rows, setRows] = useState<UnknownRow[]>([]);
  const [busy, setBusy] = useState(false);
  async function load() {
    const { data, error } = await supabase.from('receipts')
      .select('id,status,original_filename,media_type,source,created_at,updated_at')
      .eq('company_id', workspace.companyId).order('created_at', { ascending: false });
    if (error) throw error; setRows((data ?? []) as UnknownRow[]);
  }
  useEffect(() => { load().catch((error) => onNotice({ kind: 'error', message: String(error.message ?? error) })); }, [workspace.companyId]);
  async function upload(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = event.currentTarget.elements.namedItem('receipt') as HTMLInputElement;
    const file = input.files?.[0]; if (!file) return;
    setBusy(true);
    try {
      const intent = await api<{ receipt: { id: string }; upload: { signedUrl: string } }>('/v1/receipts/upload-intents', {
        method: 'POST', body: JSON.stringify({
          companyId: workspace.companyId, originalFilename: file.name, mediaType: file.type,
          sizeBytes: file.size, source: 'gallery', capturedAt: null,
        }),
      });
      const uploaded = await fetch(intent.upload.signedUrl, { method: 'PUT', headers: { 'Content-Type': file.type }, body: file });
      if (!uploaded.ok) throw new Error(`Receipt upload failed with ${uploaded.status}.`);
      await api(`/v1/receipts/${intent.receipt.id}/complete`, {
        method: 'POST', body: JSON.stringify({ clientSha256: await sha256(file) }),
      });
      input.value = ''; onNotice({ kind: 'success', message: 'Receipt uploaded and queued for verification.' }); await load();
    } catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Upload failed.' }); }
    finally { setBusy(false); }
  }
  return <section className="page-section">
    <header className="page-header"><div><p className="eyebrow">Employee capture</p><h2>Receipts</h2></div></header>
    <form className="upload-panel" onSubmit={upload}>
      <label>Receipt image<input name="receipt" type="file" accept="image/jpeg,image/png,image/webp" required /></label>
      <button className="primary" disabled={busy}>{busy ? 'Uploading…' : 'Upload receipt'}</button>
      <p className="hint">JPEG, PNG or WebP, up to 7.5 MB. Originals remain private and company-scoped.</p>
    </form>
    <div className="table-wrap"><table><thead><tr><th>Receipt</th><th>Status</th><th>Source</th><th>Created</th></tr></thead><tbody>
      {rows.map((row) => <tr key={String(row.id)}><td>{String(row.original_filename)}</td><td><span className="status-pill">{String(row.status)}</span></td><td>{String(row.source)}</td><td>{new Date(String(row.created_at)).toLocaleString()}</td></tr>)}
      {!rows.length && <tr><td colSpan={4} className="empty">No receipts yet.</td></tr>}
    </tbody></table></div>
  </section>;
}

function ClaimScreen({ workspace, onNotice }: { workspace: Workspace; onNotice: (notice: Notice) => void }) {
  const [claims, setClaims] = useState<UnknownRow[]>([]);
  const [dimensions, setDimensions] = useState<{ categories: UnknownRow[]; projects: UnknownRow[]; costCentres: UnknownRow[] }>({ categories: [], projects: [], costCentres: [] });
  const [receiptId, setReceiptId] = useState('');
  const [purpose, setPurpose] = useState('');
  const [categoryId, setCategoryId] = useState('');
  async function load() {
    const [claimPayload, dimensionPayload] = await Promise.all([
      api<{ claims: UnknownRow[] }>(`/v1/expenses/claims?companyId=${workspace.companyId}`),
      api<{ dimensions: typeof dimensions }>(`/v1/expenses/dimensions?companyId=${workspace.companyId}`),
    ]);
    setClaims(claimPayload.claims); setDimensions(dimensionPayload.dimensions);
    if (!categoryId && dimensionPayload.dimensions.categories[0]) setCategoryId(String(dimensionPayload.dimensions.categories[0].id));
  }
  useEffect(() => { load().catch((error) => onNotice({ kind: 'error', message: error.message })); }, [workspace.companyId]);
  async function create(event: FormEvent) {
    event.preventDefault();
    try {
      await api('/v1/expenses/claims/from-receipt', { method: 'POST', body: JSON.stringify({ receiptId, categoryId, businessPurpose: purpose, projectId: null, costCentreId: null, notes: null }) });
      setReceiptId(''); setPurpose(''); onNotice({ kind: 'success', message: 'Expense claim created from verified receipt evidence.' }); await load();
    } catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Could not create claim.' }); }
  }
  return <section className="page-section">
    <header className="page-header"><div><p className="eyebrow">Employee context</p><h2>Expense claims</h2></div></header>
    <form className="form-grid" onSubmit={create}>
      <label>Verified receipt ID<input value={receiptId} onChange={(event) => setReceiptId(event.target.value)} required placeholder="UUID from verified receipt" /></label>
      <label>Category<select value={categoryId} onChange={(event) => setCategoryId(event.target.value)} required>{dimensions.categories.map((row) => <option key={String(row.id)} value={String(row.id)}>{String(row.name)}</option>)}</select></label>
      <label className="span-2">Business purpose<textarea value={purpose} onChange={(event) => setPurpose(event.target.value)} required minLength={3} /></label>
      <button className="primary">Create claim</button>
    </form>
    <div className="card-grid">{claims.map((claim) => <article className="data-card" key={String(claim.id)}><div className="card-row"><strong>{String(claim.merchant_name ?? 'Unknown merchant')}</strong><span className="status-pill">{String(claim.status)}</span></div><p>{String(claim.business_purpose)}</p><p className="money">{String(claim.currency)} {String(claim.amount)}</p><code>{String(claim.id)}</code></article>)}{!claims.length && <p className="empty-card">No expense claims yet.</p>}</div>
  </section>;
}

function ReportScreen({ workspace, onNotice }: { workspace: Workspace; onNotice: (notice: Notice) => void }) {
  const [reports, setReports] = useState<UnknownRow[]>([]);
  const [claims, setClaims] = useState<UnknownRow[]>([]);
  const [selected, setSelected] = useState<UnknownRow | null>(null);
  const [title, setTitle] = useState('Monthly expenses');
  const today = new Date().toISOString().slice(0, 10);
  const [periodStart, setPeriodStart] = useState(`${today.slice(0, 8)}01`);
  const [periodEnd, setPeriodEnd] = useState(today);
  async function load() {
    const [reportPayload, claimPayload] = await Promise.all([
      api<{ reports: UnknownRow[] }>(`/v1/expenses/reports?companyId=${workspace.companyId}`),
      api<{ claims: UnknownRow[] }>(`/v1/expenses/claims?companyId=${workspace.companyId}&status=draft`),
    ]);
    setReports(reportPayload.reports); setClaims(claimPayload.claims);
  }
  useEffect(() => { load().catch((error) => onNotice({ kind: 'error', message: error.message })); }, [workspace.companyId]);
  async function create(event: FormEvent) {
    event.preventDefault();
    try { await api('/v1/expenses/reports', { method: 'POST', body: JSON.stringify({ companyId: workspace.companyId, title, periodStart, periodEnd }) }); await load(); onNotice({ kind: 'success', message: 'Draft report created.' }); }
    catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Could not create report.' }); }
  }
  async function open(reportId: string) {
    const payload = await api<{ report: UnknownRow }>(`/v1/expenses/reports/${reportId}`); setSelected(payload.report);
  }
  async function addClaim(claimId: string) {
    if (!selected) return;
    try {
      const result = await api<{ item: { version: number } }>(`/v1/expenses/reports/${selected.id}/items`, { method: 'POST', body: JSON.stringify({ claimId, expectedVersion: selected.version }) });
      await open(String(selected.id)); await load(); onNotice({ kind: 'success', message: `Claim added. Report version ${result.item.version}.` });
    } catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Could not add claim.' }); }
  }
  async function preview() {
    if (!selected) return;
    try { const result = await api<{ evaluation: unknown }>(`/v1/policies/reports/${selected.id}/evaluate`, { method: 'POST' }); setSelected({ ...selected, policyPreview: result.evaluation }); }
    catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Policy preview failed.' }); }
  }
  async function submit() {
    if (!selected) return;
    try {
      const result = await api<{ result: UnknownRow }>(`/v1/expenses/reports/${selected.id}/submit`, { method: 'POST', body: JSON.stringify({ expectedVersion: selected.version }) });
      if (result.result.status === 'blocked') setSelected({ ...selected, policyPreview: result.result.policy });
      else { setSelected(null); await load(); }
      onNotice({ kind: result.result.status === 'blocked' ? 'info' : 'success', message: result.result.status === 'blocked' ? 'Policy blocks must be resolved before submission.' : 'Report submitted for authenticated approval.' });
    } catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Submission failed.' }); }
  }
  const reportItems = (selected?.items as UnknownRow[] | undefined) ?? [];
  return <section className="page-section"><header className="page-header"><div><p className="eyebrow">Employee report</p><h2>Reports</h2></div></header>
    <form className="form-grid" onSubmit={create}><label>Title<input value={title} onChange={(event) => setTitle(event.target.value)} /></label><label>Start<input type="date" value={periodStart} onChange={(event) => setPeriodStart(event.target.value)} /></label><label>End<input type="date" value={periodEnd} onChange={(event) => setPeriodEnd(event.target.value)} /></label><button className="primary">Create draft</button></form>
    <div className="split"><div><h3>Reports</h3>{reports.map((report) => <button className="list-button" key={String(report.id)} onClick={() => open(String(report.id))}><span>{String(report.title)}</span><span>{String(report.status)} · v{String(report.version)}</span></button>)}</div>
      <div>{selected ? <article className="detail-panel"><div className="card-row"><h3>{String(selected.title)}</h3><span className="status-pill">{String(selected.status)}</span></div><p>{String(selected.period_start)} → {String(selected.period_end)}</p><h4>Attached claims</h4>{reportItems.map((item) => <pre key={String(item.position)}>{JSON.stringify(item.claim, null, 2)}</pre>)}<h4>Add draft claim</h4>{claims.map((claim) => <button className="list-button" key={String(claim.id)} onClick={() => addClaim(String(claim.id))}>{String(claim.merchant_name)} · {String(claim.currency)} {String(claim.amount)}</button>)}<div className="action-row"><button onClick={preview}>Preview policy</button><button className="primary" onClick={submit}>Submit</button></div>{selected.policyPreview ? <pre className="policy-output">{JSON.stringify(selected.policyPreview, null, 2)}</pre> : null}</article> : <p className="empty-card">Select a report to assemble and submit.</p>}</div></div>
  </section>;
}

function ReviewScreen({ onNotice }: { onNotice: (notice: Notice) => void }) {
  const [assignments, setAssignments] = useState<UnknownRow[]>([]);
  const [workflow, setWorkflow] = useState<UnknownRow | null>(null);
  const [note, setNote] = useState('');
  async function load() { setAssignments((await api<{ assignments: UnknownRow[] }>('/v1/approvals/assignments')).assignments); }
  useEffect(() => { load().catch((error) => onNotice({ kind: 'error', message: error.message })); }, []);
  async function open(id: string) { setWorkflow((await api<{ workflow: UnknownRow }>(`/v1/approvals/workflows/${id}`)).workflow); }
  async function decide(action: 'approve' | 'request_changes' | 'reject') {
    if (!workflow) return;
    try {
      await api(`/v1/approvals/workflows/${workflow.id}/decisions`, { method: 'POST', body: JSON.stringify({ expectedVersion: workflow.version, action, note: note || null, claimId: null, idempotencyKey: `${workflow.id}:${action}:${crypto.randomUUID()}` }) });
      setWorkflow(null); setNote(''); await load(); onNotice({ kind: 'success', message: 'Decision recorded as immutable approval evidence.' });
    } catch (error) { onNotice({ kind: 'error', message: error instanceof Error ? error.message : 'Decision failed.' }); }
  }
  return <section className="page-section"><header className="page-header"><div><p className="eyebrow">Authenticated review</p><h2>Approval queue</h2></div></header><div className="split"><div>{assignments.map((assignment) => { const item = assignment.workflow as UnknownRow; return <button className="list-button" key={String(assignment.id)} onClick={() => open(String(assignment.workflow_id))}><span>{String(assignment.stage)} review</span><span>{String(item?.status ?? '')}</span></button>; })}{!assignments.length && <p className="empty-card">No assigned reviews.</p>}</div><div>{workflow ? <article className="detail-panel"><h3>Workflow {String(workflow.id)}</h3><pre>{JSON.stringify(workflow.report, null, 2)}</pre><label>Decision note<textarea value={note} onChange={(event) => setNote(event.target.value)} /></label><div className="action-row"><button className="primary" onClick={() => decide('approve')}>Approve</button><button onClick={() => decide('request_changes')}>Request changes</button><button className="danger" onClick={() => decide('reject')}>Reject</button></div></article> : <p className="empty-card">Select a review.</p>}</div></div></section>;
}

function PolicyScreen({ workspace, onNotice }: { workspace: Workspace; onNotice: (notice: Notice) => void }) {
  const [rules, setRules] = useState<UnknownRow[]>([]);
  useEffect(() => { api<{ rules: UnknownRow[] }>(`/v1/policies/rules?companyId=${workspace.companyId}`).then((payload) => setRules(payload.rules)).catch((error) => onNotice({ kind: 'error', message: error.message })); }, [workspace.companyId]);
  return <section className="page-section"><header className="page-header"><div><p className="eyebrow">Company controls</p><h2>Policy rules</h2></div></header><div className="card-grid">{rules.map((rule) => <article className="data-card" key={String(rule.id)}><div className="card-row"><strong>{String(rule.name)}</strong><span className="status-pill">v{String(rule.version)}</span></div><p>{String(rule.rule_type)} · {String(rule.severity)}</p><pre>{JSON.stringify(rule.config, null, 2)}</pre></article>)}</div></section>;
}

export function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [tab, setTab] = useState<Tab>('receipts');
  const [notice, setNotice] = useState<Notice>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setLoading(false); });
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);
  useEffect(() => {
    if (!session) { setWorkspaces([]); setWorkspace(null); return; }
    supabase.from('company_memberships').select('company_id,role,companies(id,name)').eq('active', true)
      .then(({ data, error }) => {
        if (error) { setNotice({ kind: 'error', message: error.message }); return; }
        const list = (data ?? []).map((row) => {
          const company = row.companies as unknown as { id: string; name: string };
          return { companyId: row.company_id as string, companyName: company.name, role: row.role as Role };
        });
        setWorkspaces(list); setWorkspace((current) => current ?? list[0] ?? null);
      });
  }, [session?.user.id]);
  const tabs = useMemo(() => {
    const items: { id: Tab; label: string }[] = [{ id: 'receipts', label: 'Receipts' }, { id: 'claims', label: 'Claims' }, { id: 'reports', label: 'Reports' }];
    if (workspace && ['manager', 'finance', 'admin'].includes(workspace.role)) items.push({ id: 'reviews', label: 'Reviews' });
    if (workspace && ['finance', 'admin'].includes(workspace.role)) items.push({ id: 'policies', label: 'Policies' });
    return items;
  }, [workspace]);
  if (loading) return <main className="center"><p>Restoring secure session…</p></main>;
  if (!session) return <><NoticeBar notice={notice} /><Login onNotice={setNotice} /></>;
  if (!workspace) return <main className="center"><div><h1>No workspace access</h1><p>Ask a company administrator to add your authenticated user.</p><button onClick={() => supabase.auth.signOut()}>Sign out</button></div></main>;
  return <div className="app-shell"><aside className="sidebar"><div><div className="brand"><span className="brand-mark">S</span><span><strong>Spendsnap</strong><small>Auditable expenses</small></span></div><label className="workspace-label">Workspace<select value={workspace.companyId} onChange={(event) => setWorkspace(workspaces.find((item) => item.companyId === event.target.value) ?? null)}>{workspaces.map((item) => <option key={item.companyId} value={item.companyId}>{item.companyName} · {item.role}</option>)}</select></label><nav aria-label="Primary">{tabs.map((item) => <button key={item.id} className={tab === item.id ? 'active' : ''} onClick={() => setTab(item.id)}>{item.label}</button>)}</nav></div><button className="sign-out" onClick={() => supabase.auth.signOut()}>Sign out</button></aside><main className="main"><NoticeBar notice={notice} />{tab === 'receipts' && <ReceiptScreen workspace={workspace} onNotice={setNotice} />}{tab === 'claims' && <ClaimScreen workspace={workspace} onNotice={setNotice} />}{tab === 'reports' && <ReportScreen workspace={workspace} onNotice={setNotice} />}{tab === 'reviews' && <ReviewScreen onNotice={setNotice} />}{tab === 'policies' && <PolicyScreen workspace={workspace} onNotice={setNotice} />}</main></div>;
}
