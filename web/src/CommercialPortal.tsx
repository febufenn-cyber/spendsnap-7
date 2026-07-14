import { FormEvent, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { api } from './lib/api';
import { supabase } from './lib/supabase';

type Row = Record<string, unknown>;
type Workspace = { companyId: string; companyName: string; role: string };

export function CommercialPortal() {
  const [session, setSession] = useState<Session | null>(null);
  const [email, setEmail] = useState('');
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [plans, setPlans] = useState<Row[]>([]);
  const [account, setAccount] = useState<Row | null>(null);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return;
    supabase.from('company_memberships')
      .select('company_id,role,companies(id,name)')
      .eq('active', true)
      .then(({ data, error }) => {
        if (error) return setNotice(error.message);
        const list = (data ?? []).map((row) => {
          const company = row.companies as unknown as { name: string };
          return { companyId: String(row.company_id), companyName: company.name, role: String(row.role) };
        });
        setWorkspaces(list);
        setWorkspace(list[0] ?? null);
      });
  }, [session?.user.id]);

  async function load() {
    if (!workspace) return;
    const [planPayload, accountPayload] = await Promise.all([
      api<{ plans: Row[] }>('/v1/commercial/plans'),
      api<{ account: Row }>(`/v1/commercial/account?companyId=${workspace.companyId}`),
    ]);
    setPlans(planPayload.plans);
    setAccount(accountPayload.account);
  }
  useEffect(() => { load().catch((error) => setNotice(error.message)); }, [workspace?.companyId]);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/commercial.html` },
    });
    setNotice(error?.message ?? 'Check your work email for the secure sign-in link.');
  }

  async function completeStep(stepCode: string) {
    if (!workspace) return;
    await api(`/v1/commercial/onboarding/${stepCode}/complete`, {
      method: 'POST',
      body: JSON.stringify({ companyId: workspace.companyId, evidence: { confirmedInPortal: true } }),
    });
    setNotice(`Onboarding step completed: ${stepCode}`);
    await load();
  }

  async function selectPlan(planCode: string) {
    if (!workspace) return;
    const subscription = account?.subscription as Row | undefined;
    await api('/v1/commercial/subscriptions/select', {
      method: 'POST',
      body: JSON.stringify({
        companyId: workspace.companyId,
        planCode,
        expectedVersion: Number(subscription?.version ?? 0),
      }),
    });
    setNotice('Plan selection recorded. Pricing remains subject to validated commercial terms.');
    await load();
  }

  if (!session) return <main className="auth-shell"><section className="auth-card"><p className="eyebrow">Commercial account</p><h1>Spendsnap Account</h1><form className="stack" onSubmit={signIn}><label>Work email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label><button className="primary">Send magic link</button></form>{notice && <p>{notice}</p>}</section></main>;
  if (!workspace) return <main className="center"><p>No active workspace.</p></main>;

  const subscription = account?.subscription as Row | undefined;
  const currentPlan = subscription?.plan as Row | undefined;
  const onboarding = (account?.onboarding as Row[] | undefined) ?? [];
  const usage = (account?.usageLast31Days as Row | undefined) ?? {};

  return <div className="app-shell"><aside className="sidebar"><div><div className="brand"><span className="brand-mark">S</span><span><strong>Spendsnap Account</strong><small>Onboarding &amp; usage</small></span></div><label className="workspace-label">Workspace<select value={workspace.companyId} onChange={(event) => setWorkspace(workspaces.find((item) => item.companyId === event.target.value) ?? null)}>{workspaces.map((item) => <option key={item.companyId} value={item.companyId}>{item.companyName} · {item.role}</option>)}</select></label><nav><a href="/">Employee</a><a href="/admin.html">Admin</a></nav></div><button className="sign-out" onClick={() => supabase.auth.signOut()}>Sign out</button></aside><main className="main"><section className="page-section"><header className="page-header"><div><p className="eyebrow">Commercial operating system</p><h2>Account and launch readiness</h2></div></header>{notice && <div className="notice info">{notice}</div>}<div className="notice info">Displayed prices are current product hypotheses, not a binding offer. Confirm final pricing and service terms before purchase.</div><div className="card-grid"><article className="data-card"><strong>Subscription</strong><p className="money">{String(subscription?.status ?? 'unknown')}</p></article><article className="data-card"><strong>Current plan</strong><p className="money">{String(currentPlan?.name ?? 'Starter')}</p></article><article className="data-card"><strong>Trial ends</strong><p>{subscription?.trial_ends_at ? new Date(String(subscription.trial_ends_at)).toLocaleString() : 'Not in trial'}</p></article></div><h3>Onboarding</h3><div className="card-grid">{onboarding.map((step) => <article className="data-card" key={String(step.step_code)}><div className="card-row"><strong>{String(step.step_code).replaceAll('_', ' ')}</strong><span className="status-pill">{step.completed_at ? 'complete' : step.required ? 'required' : 'optional'}</span></div>{!step.completed_at && <button onClick={() => completeStep(String(step.step_code)).catch((error) => setNotice(error.message))}>Mark complete</button>}</article>)}</div><h3>Usage — last 31 days</h3><div className="card-grid">{Object.entries(usage).map(([metric, quantity]) => <article className="data-card" key={metric}><strong>{metric.replaceAll('_', ' ')}</strong><p className="money">{String(quantity)}</p></article>)}{Object.keys(usage).length === 0 && <p className="empty-card">No metered usage yet.</p>}</div><h3>Plans</h3><div className="card-grid">{plans.map((plan) => <article className="data-card" key={String(plan.id)}><div className="card-row"><strong>{String(plan.name)}</strong><span className="status-pill">v{String(plan.version)}</span></div><p>{String(plan.description)}</p><p className="money">₹{(Number(plan.monthly_price_minor) / 100).toLocaleString('en-IN')} / month</p><p>{String(plan.included_receipts)} receipts · {String(plan.included_active_users)} active users</p><button className="primary" disabled={workspace.role !== 'admin' || currentPlan?.code === plan.code} onClick={() => selectPlan(String(plan.code)).catch((error) => setNotice(error.message))}>{currentPlan?.code === plan.code ? 'Current plan' : 'Select plan'}</button></article>)}</div></section></main></div>;
}
