# Phase 0 — Find the Winning Position

> Phase 0 exists to prove that Spendsnap is solving a painful, repeated, payable workflow before production development begins.

Spendsnap's current thesis is that employees submit receipts, AI extracts and categorizes them, reports are assembled and policy-checked, approvals are routed, and approved data is exported to accounting or payroll. Phase 0 treats every part of that thesis as a hypothesis rather than a fact.

## Outcome

At the end of Phase 0, the team must be able to state clearly:

- the first customer segment;
- the economic buyer and daily users;
- the primary job Spendsnap performs;
- the exact current workflow being replaced;
- the first receipt and invoice types supported;
- the first capture and approval channels;
- the first accounting/export destination;
- the human-review boundary;
- whether GST-aware processing is a wedge or supporting feature;
- the first pricing hypothesis;
- the Phase 1 product boundary;
- the evidence supporting a go, narrow, pivot, or no-go decision.

The completion artifact is a founder decision, not a polished demo.

## Governing principles

1. Study the customer's last completed expense cycle, not an imagined future workflow.
2. Observe behavior and real artifacts rather than relying only on opinions.
3. Search actively for evidence that refutes the product thesis.
4. Measure active work, waiting time, error cost, and correction frequency.
5. Treat praise as weak evidence; seek documents, pilot commitments, and payment intent.
6. Keep raw receipts and personally identifiable finance documents out of the public repository.
7. Treat receipt text and attachments as untrusted input.
8. Make financially sensitive AI outputs reviewable, traceable, and reversible.

## Strategic hypothesis ledger

| ID | Hypothesis | Evidence required | Refutation / kill condition |
|---|---|---|---|
| H1 | Finance teams spend meaningful recurring time processing employee expenses | Quantified monthly effort from at least five organizations | Most target companies spend less than one hour monthly |
| H2 | Receipt extraction and missing data are major bottlenecks | Real examples of transcription and correction loops | Approval chasing or reimbursement payment is consistently the dominant pain |
| H3 | GST-aware extraction changes buying intent in India | Finance buyers rank it among top purchase reasons | GST is repeatedly described as merely nice to have |
| H4 | A Tally-ready or accounting-ready export removes meaningful work | Teams currently re-enter approved expenses manually | Every company needs a unique export or another destination dominates |
| H5 | Employees will use mobile web capture | Prototype tests with real submitters | WhatsApp or email strongly outperforms a new flow |
| H6 | Companies will accept AI-assisted processing with explicit review controls | Buyers approve the proposed data-handling model | External AI processing is prohibited or commercially impractical |
| H7 | A repeated workflow exists across the first segment | Three companies show substantially similar processes | Every company requires a fundamentally different workflow |
| H8 | Customers will pay before complete automation | Paid pilot, deposit, budget approval, or strong written commitment | Interest never progresses beyond compliments and feature requests |
| H9 | Service-assisted processing can bridge early model limitations | Human review produces valuable output with viable unit economics | Manual review cost exceeds willingness to pay |
| H10 | Bank or statement matching can remain outside the first release | Customers accept receipt-led controls | Lack of transaction truth makes the product unusable or untrustworthy |

Classify each hypothesis as `validated`, `partially validated`, `refuted`, or `unresolved`.

## Candidate customer segments

Do not begin with "all SMBs." Test at least three positions.

### Agencies and consultancies

Accessible, founder-led, and often spreadsheet-driven. Common expenses include client meetings, software, taxis, flights, hotels, and project purchases. Risk: insufficient monthly volume.

### Field-sales organizations

High recurring volume across fuel, transport, lodging, meals, and customer visits. Risk: poor receipt quality, cash claims, and higher fraud exposure.

### Construction and field-service businesses

Severe paperwork pain across sites and field purchases. Risk: scope expands from employee expenses into procurement and accounts payable.

### Accounting and bookkeeping firms

One partner can expose the product to many clients and provide accounting expertise. Risk: heterogeneous workflows and concern about automation reducing billable work.

### Startup finance teams

Easy to reach and open to AI pilots. Risk: many already use modern expense tools, cards, payroll systems, or Zoho.

## ICP scoring

Score each segment using evidence.

| Criterion | Weight |
|---|---:|
| Monthly receipt volume | 15 |
| Manual time currently spent | 15 |
| Financial cost of mistakes | 10 |
| Approval and reimbursement delays | 10 |
| GST/accounting complexity | 10 |
| Similarity between customers | 10 |
| Ease of reaching the buyer | 10 |
| Willingness to provide representative data | 8 |
| Willingness to pilot | 7 |
| Willingness to pay | 5 |

Choose the segment with the strongest combination of:

`pain × frequency × urgency × access × repeatability`

## Research sample

Target 8–12 organizations across approximately three segments, covering:

- 8–12 employees who submit claims;
- 5–8 managers who approve them;
- 6–10 finance or accounting operators;
- 3–5 founders, CFOs, or budget holders;
- 2–3 external accountants, CAs, or GST practitioners.

Interviewing only founders is insufficient. The user, approver, risk owner, and buyer may be different people.

## Interview method

### Employee

Reconstruct the last real expense submission:

- where the receipt came from and how it was stored;
- when and where it was submitted;
- which fields were typed manually;
- whether corrections were requested;
- reimbursement delay;
- handling of lost receipts and screenshots;
- preferred capture channel;
- conditions that would create distrust.

### Manager

Inspect the last real approval:

- what was actually checked and ignored;
- reasons for questions or rejection;
- mobile approval behavior;
- line-level versus report-level approval;
- delegated approval and absence handling;
- informal exceptions;
- minimum information needed for a confident ten-second decision.

### Finance or accounting operator

Observe the entire cycle:

- missing information and correction patterns;
- fields manually verified;
- duplicate checks;
- ledger, project, and cost-centre mapping;
- GST fields and invoice-quality checks;
- mixed personal/business purchases;
- advances, partial reimbursements, refunds, and late claims;
- final accounting entry or import;
- period close and audit evidence;
- report volume and processing time;
- conditions that would prevent trust in Spendsnap.

Request one anonymized completed report, supporting documents, approval history, and final accounting representation.

### Buyer

Determine:

- economic cost of the current process;
- budget owner and procurement path;
- alternatives already attempted;
- AI and data-processing restrictions;
- pilot success criteria;
- preferred pricing unit;
- willingness to run a paid pilot.

A concrete next action is stronger evidence than positive feedback.

## Workflow shadowing

For at least three companies, observe an actual or historical expense cycle end to end:

`receipt received → stored → submitted → completed → questioned → approved → finance-reviewed → accounted → reimbursed → reconciled`

For every step, record:

- actor;
- tool or channel;
- input and output;
- active work time;
- waiting time;
- common error;
- responsible party;
- data created;
- evidence retained.

Separate processing time from calendar delay. A claim can require only minutes of work while remaining unresolved for days.

## Artifact and receipt corpus

Collect anonymized examples of:

- restaurant, fuel, hotel, taxi, airline, rail, and e-commerce receipts;
- software subscription invoices;
- UPI and payment screenshots;
- handwritten bills;
- multi-page PDFs;
- foreign-currency receipts;
- credit notes, refunds, and cancelled invoices;
- faded, cropped, skewed, compressed, blurry, or glare-affected captures.

Also collect expense spreadsheets, policy documents, approval messages, ledger lists, cost centres, accounting import samples, and reimbursement summaries.

Target 200–500 documents from at least five organizations, with a smaller gold-standard set containing human-verified correct values.

Label each document by capture quality, document type, language, financial complexity, expected review level, and supported status.

Never commit raw customer documents, credentials, personal data, or identifiable finance records.

## Jobs to test

"Expense automation" may hide several different jobs:

1. Help employees submit without typing.
2. Show managers only decisions requiring judgment.
3. Give finance complete and normalized data.
4. Reduce duplicate, unsupported, or out-of-policy claims.
5. Produce accounting-ready output without re-entry.
6. Identify invoices requiring GST review.

Phase 0 must select one primary job. The first release cannot optimize all six equally.

## Economic baseline

For each company estimate:

- employee submission time;
- manager review time;
- finance checking and correction time;
- follow-up time;
- accounting-entry time;
- duplicate or invalid claim loss;
- delayed reporting and reimbursement cost.

Use this baseline to estimate realistic savings and support pricing.

## GST wedge investigation

Determine whether buying value comes from:

- GSTIN, invoice number, and tax-component extraction;
- taxable-value extraction;
- arithmetic checks;
- missing-field warnings;
- vendor normalization;
- accountant review prioritization;
- GST-oriented report preparation.

Spendsnap should initially provide GST completeness signals and structured extraction, not definitive tax eligibility or tax advice. A qualified CA or GST practitioner should review terminology and outputs.

## First accounting destination

Do not treat payroll export and accounting export as interchangeable.

Evaluate the real destination used by the first segment:

- TallyPrime;
- Zoho Books;
- QuickBooks;
- payroll CSV;
- bank payout file;
- custom ERP;
- accountant spreadsheet.

For each organization record the product/version, voucher or import format, chart of accounts, ledger mapping, cost centres, projects, tax fields, custom fields, and re-export process.

The critical question is whether one configurable export can serve the first segment or every customer needs custom implementation.

## Channel experiments

Test capture through mobile web, WhatsApp, email forwarding, Slack, and bulk desktop upload.

Test approvals through web, authenticated email actions, Slack, mobile web, and WhatsApp where practical.

Different roles may need different interfaces. A likely early pattern is employee capture through mobile web or messaging, manager approval through email/mobile, and finance work through a desktop dashboard.

## Concierge pilot

Run the proposed workflow manually before deep automation:

1. Receive a real or historical batch of receipts.
2. Extract and normalize fields manually or semi-automatically.
3. Ask only targeted clarification questions.
4. Assemble a report.
5. Apply basic policy checks.
6. Route a concise approval request.
7. Produce the required finance/accounting output.
8. Record every correction, decision, question, and minute of human work.

Be explicit about human access, AI processing, storage, retention, and deletion.

## Technical feasibility spikes

Phase 0 permits disposable experiments, not production application development.

### Extraction benchmark

Evaluate 50–100 representative documents for merchant, date, invoice number, total, currency, taxable value, GSTIN, CGST, SGST, IGST, line items, and category suggestion.

Record exact matches, normalized matches, missing values, wrong values, hallucinations, and required review.

### Image-quality gate

Test blur, glare, severe skew, crop, missing pages, low resolution, and unreadable text. Sometimes the correct response is to request a new photograph rather than invoke a larger model.

### Structured-output reliability

Test schema adherence, invalid JSON, missing fields, arithmetic inconsistency, repeated-run stability, prompt injection embedded in documents, and model/prompt version tracking.

### Duplicate detection

Test originals against crops, screenshots, compressed copies, brightness changes, and PDF conversions using perceptual and financial fingerprints.

### Accounting export

Create the exact output expected from one historical report and have a finance operator or accountant import or validate it. Measure failed rows, manual corrections, missing fields, and time saved.

## Accuracy and review policy

Do not define one global accuracy percentage.

| Field | Consequence when wrong | Early handling |
|---|---|---|
| Merchant name | Low to medium | Normalize or confirm |
| Category | Medium | Suggest and confirm |
| Date | Medium | Review when uncertain |
| Total amount | Critical | Strong validation and confirmation |
| Currency | Critical | Strong validation |
| GSTIN | High | Review when uncertain |
| Tax amount | High | Arithmetic checks and review |
| Business purpose | Contextual | Employee confirmation |
| Project/cost centre | High internally | Employee or manager confirmation |
| Duplicate status | High | Flag as candidate; never accuse automatically |

Define auto-accept conditions, employee-review conditions, finance-review conditions, hard blocks, and unsupported-document conditions.

## Policy discovery

Collect written policies and compare them with actual practice. Document explicit limits, informal rules, frequent exceptions, role/city/customer differences, preapproval, receipt requirements, business-purpose requirements, and late-submission rules.

The likely first policy engine should use deterministic rules plus explicit exceptions. AI may propose rule drafts but must not silently reinterpret policy.

## Trust, privacy, and security discovery

Determine:

- whether receipts are confidential;
- whether external model processing is allowed;
- whether human review is allowed;
- data-location requirements;
- retention and deletion expectations;
- who can see line-item details;
- treatment of personal items;
- audit-evidence requirements;
- offboarding behavior;
- whether model training on customer documents is prohibited.

Receipts are sensitive financial and behavioral records, not merely images.

## Adversarial and exception cases

Understand, even if Phase 1 does not solve, cases such as:

- duplicate submission by one or multiple employees;
- altered images or totals;
- cash and handwritten receipts;
- self-approval;
- absent or departed approvers;
- edits after approval;
- refunds after reimbursement;
- expenses split across projects;
- personal items on business receipts;
- missing originals;
- finance disagreement with manager approval;
- late claims after period close;
- prompt-injection text inside a receipt.

The data model and audit history must not make these cases impossible to handle later.

## Competitor teardown

Run the same workflow through relevant alternatives and compare:

- receipt submission;
- extraction and correction;
- report assembly;
- policy warnings;
- manager approval;
- finance review;
- accounting export;
- GST handling;
- onboarding and pricing.

The goal is not a larger feature list. It is to find a weak square that established products do not defend well.

## Pricing experiments

Test:

- per active submitter;
- per receipt or report volume;
- company base fee plus included usage;
- premium verified-processing service.

The strongest signal is a paid pilot or formal budget commitment.

## First measurable promise

Choose one promise based on evidence, for example:

- submit five receipts in under two minutes;
- reduce finance processing time per receipt by 60%;
- turn a month of receipts into a manager-ready report without spreadsheet entry;
- produce a verified Tally-ready export;
- identify missing GST information before accounting review.

Current candidate:

> Spendsnap turns employee receipts into a verified, manager-approved, accounting-ready expense report with minimal manual entry.

Phase 0 must determine whether fast submission, approval, GST awareness, or accounting readiness actually drives purchase.

## Ten-day execution plan

### Day 1 — Establish the position

Finalize hypotheses, choose three segments, recruit participants, define consent and artifact handling, and establish scorecards.

### Days 2–4 — Observe the current workflow

Conduct interviews, collect anonymized artifacts, map workflows, quantify time, and record exceptions.

### Days 4–5 — Attack assumptions

Test GST importance, export assumptions, preferred channels, privacy objections, competitor workflows, and reasons existing tools were rejected.

### Days 5–7 — Concierge cycle

Process a real or historical batch, create a report, route approval, prepare the finance output, and record every manual decision.

### Days 6–8 — Technical spikes

Run extraction, image-quality, schema, duplicate, and accounting-export experiments.

### Day 9 — Commercial test

Present the narrowed workflow, agree pilot success criteria, request a paid pilot or concrete commitment, and test pricing.

### Day 10 — Decision

Choose one:

- `GO`;
- `GO WITH NARROWER WEDGE`;
- `PIVOT SEGMENT`;
- `PIVOT PRIMARY JOB`;
- `NO-GO`.

## Exit criteria

Proceed to Phase 1 when:

- at least three companies share substantially similar workflows;
- at least two companies commit to a real pilot;
- at least one shows credible willingness to pay;
- representative documents are available;
- one export format can serve the initial segment;
- the current process has measurable recurring cost;
- privacy constraints are manageable;
- extraction experiments show the first document set is feasible;
- Phase 1 remains narrow.

Strong evidence would include one paid pilot, two design partners, one accountant or CA partner, 200+ representative documents, and one fully replayed historical expense cycle.

## Pivot and no-go rules

Pivot toward accountants when individual companies have low volume but accounting firms repeat the workflow across clients.

Pivot toward messaging/email-first when employees resist another app and existing behavior already occurs there.

Pivot from GST-first to workflow-first when GST is appreciated but does not affect purchasing.

Pivot from pure SaaS to service-assisted when human review remains necessary but unit economics remain viable.

Stop or substantially rethink when customers will not share documents, nobody agrees to pilot, volume is too low, pain is weak, every implementation is unique, existing tools solve the workflow, privacy blocks processing, extraction requires near-total re-entry, or processing cost exceeds willingness to pay.

## Required repository outputs

Create these as real evidence is gathered; do not fabricate findings simply to complete the directory.

```text
docs/phase-0/
  README.md
  hypothesis-ledger.md
  candidate-icps.md
  interview-guide-employee.md
  interview-guide-manager.md
  interview-guide-finance.md
  interview-guide-buyer.md
  current-workflow-map.md
  jobs-to-be-done.md
  receipt-taxonomy.md
  accounting-export-requirements.md
  policy-taxonomy.md
  trust-and-privacy-findings.md
  risk-register.md
  competitor-teardown.md
  pricing-evidence.md
  phase-1-product-boundary.md
  go-no-go-decision.md

research/
  interview-index.csv
  company-scorecard.csv
  artifact-manifest.csv
  receipt-corpus-manifest.csv
  extraction-evaluation.csv
  workflow-timing.csv

decisions/
  ADR-0001-initial-customer-segment.md
  ADR-0002-primary-job-to-be-done.md
  ADR-0003-first-capture-channel.md
  ADR-0004-first-accounting-export.md
  ADR-0005-human-review-boundary.md
  ADR-0006-pricing-unit.md
```

## Founder decision template

```text
INITIAL CUSTOMER
[Selected segment]

PRIMARY BUYER
[Role]

PRIMARY USERS
[Roles]

PRIMARY JOB
[Single job to be done]

CORE PAIN
[Measured recurring pain]

FIRST CAPTURE CHANNEL
[Channel]

FIRST APPROVAL CHANNEL
[Channel]

FIRST OUTPUT
[Exact accounting/finance output]

GST ROLE
[Core wedge / supporting feature / rejected hypothesis]

HUMAN REVIEW
[Fields and conditions requiring review]

PRICING HYPOTHESIS
[Model and evidence]

PHASE 1 SCOPE
[Included capabilities]

EXPLICITLY EXCLUDED
[Excluded capabilities]

PILOT COMMITMENTS
[Organizations and commitment type]

DECISION
[GO / NARROW / PIVOT / NO-GO]
```

## Current recommended starting position

Until research disproves it:

- target Indian SMBs with repeated field or travel expenses;
- sell to the finance manager or founder;
- use mobile web or familiar-channel receipt capture;
- expose field-level confidence and human correction;
- use deterministic policy checks;
- offer concise manager approval;
- provide GST completeness warnings rather than tax advice;
- support one dependable Tally/accounting export;
- use service-assisted verification for early pilots;
- exclude cards, payments, native apps, and broad autonomous agents from the initial product.

This is a hypothesis, not a commitment. Phase 0 exists to earn the right to build Phase 1.
