# Spendsnap

> employees snap receipts, an agent builds the whole expense report and routes it for approval, no corporate card needed.

**Alternative to the product-shape pioneered by Emburse (YC W16)** — rank #7 of 500 in the [YC-500 Fable 5 Venture Blueprint](https://github.com/) (score 7.3/10).

## Why this exists
Expense reports are hated; receipt-to-report is prime AI work The buildable wedge: ai expense-report builder from receipts, no cards issued.

## MVP scope
- [ ] Receipt capture
- [ ] AI extract + categorize
- [ ] report assembly
- [ ] approval routing
- [ ] export to payroll

## Architecture
`Workers+Supabase+Claude` — Cloudflare Workers + Hono API, Supabase (Postgres + RLS + Auth + pgvector), Claude API via Agent SDK (claude-fable-5 for agent reasoning, claude-haiku-4-5 for volume), wrangler deploys.

**Integrations:** Claude vision; Slack; email
**Data:** Receipts; expense lines; approvals
**Agent core:** Agent turns a pile of receipts into a policy-checked report end-to-end

## Business
| | |
|---|---|
| Monetization | Per-seat SaaS |
| First customer | SMBs with manual expense reports |
| GTM wedge | 'expense report automation' SEO; outbound |
| Competition risk | High: Expensify, Zoho Expense |
| Regulatory/trust risk | Low: reporting only |
| India angle | GST input-credit extraction from Indian invoices |
| Difficulty / build time | Low / 2-3 weeks |

## 30-day plan
- **W1:** core loop — Receipt capture + AI extract + categorize
- **W2:** report assembly + approval routing + export to payroll + auth + billing
- **W3:** polish, instrument events, seed first users via: 'expense report automation' SEO; outbound
- **W4:** launch + first revenue; kill/scale decision

---
*Built with Fable 5 (Claude Code). Blueprint row: inspired by Emburse — "Virtual and physical employee card issuing and expense control"*