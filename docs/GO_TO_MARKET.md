# Firefight — Go-to-Market Strategy

## Target

**$50,000 MRR ($600k ARR) within 24 months.**

At the hybrid pricing ($9/user Team or $199/mo flat), this is roughly:
- ~250 flat-tier customers ($199 × 250 = $49.7k), or
- ~150 flat + 50 larger per-user deals averaging $400/mo, or
- Any mix that averages ~$200/customer/month across a few hundred customers.

The unit economics work for a 1-2 person team with modest infrastructure cost (~$70/mo Hetzner today, scales linearly).

## Beachhead — not "SMBs"

"SMBs" is too broad to market to. The beachhead is:

> **YC-stage Seed to Series A SaaS startups with 10–50 engineers.**

Why this segment:
- Known buyer profile (CTO or head of engineering, not a procurement committee)
- Slack-centric by default (our core integration lines up)
- Price-sensitive but willing to pay for tools that save them pain (incident chaos is very painful at this size)
- Dense community — one happy customer tells five others
- Fast sales cycle — days or weeks, not months
- Low compliance bar — no SOC 2 needed on day one

Adjacent segments we deliberately ignore for year 1:
- Enterprise (needs SSO/SAML/SCIM/audit logs)
- Regulated industries (fintech, healthtech — need SOC 2, HIPAA)
- Engineering teams < 10 (too small to pay, use Slack + shared doc)

## The five pillars

### 1. Lean hard into open source

This is the real moat. incident.io, Rootly, FireHydrant are all closed source with $40M+ in VC funding. We can't outspend them, but we can out-ship and out-trust them by being open.

Concrete actions:
- Public repo, MIT license, prominent on the marketing site
- "Self-host for free" as a first-class option, not a footnote
- Docker Compose + Kamal setup docs that take 15 minutes
- Quarterly "community release" announcements with changelog
- Answer issues publicly within 48 hours

Marketing angle: **"The open-source alternative to incident.io."** That phrase gets typed into search bars.

### 2. Ship on-call scheduling (first 6 months)

Incident response without on-call is half a product. Customers who need Firefight also need PagerDuty. Adding on-call:

- Doubles TAM (captures the PagerDuty refugee segment — they're actively looking for cheaper)
- Removes the "two-tool tax" objection in sales
- Enables the Rootly-style "$20/user for on-call" expansion tier
- Matches competitor feature parity so prospects stop asking about it

MVP scope (3-4 weeks):
- Schedules: who's on-call, when, recurring rotations
- Escalation policies: if no ack in 5min, page next person
- Alert routing: webhook in, who gets paged
- Slack + email notifications (SMS + phone calls later — Twilio)

This is the single highest-leverage feature we can build.

### 3. Ship a simple status page (after on-call)

2 weeks of work. Unlocks a whole second purchase motivation:

- "We need a status page for customers" is a common ask
- Competitors charge $30-80/mo standalone for this (StatusPage, BetterStack)
- Bundling it free with Team/Business tiers is a sales weapon
- Drives inbound — "status.firefight.app" becomes a living example

MVP scope:
- Public page per workspace (status.customer.com via CNAME)
- Component list with current status (operational / degraded / down)
- Incident history published automatically when a Firefight incident is marked public
- Email/webhook subscribers

Stripped down — no maintenance windows, no uptime SLAs in year 1.

### 4. Content marketing from day one

SEO is the only scalable acquisition channel for a bootstrapped product at this price point. Start the compounding clock now.

Publishing cadence: **2 posts per week, minimum.** Themes:

- **Postmortems as content** — write up actual incidents (Firefight's own, or permission-granted customer ones) using Firefight's postmortem tool. Shows the product.
- **SRE patterns** — "How to run a blameless postmortem," "On-call rotation patterns for small teams," etc. Long-tail SEO.
- **Tooling comparisons** — "incident.io vs PagerDuty vs Firefight," "Self-hosted vs SaaS incident management." Captures comparison-mode searches.
- **Open source releases** — every feature ship gets a post. Kills two birds (changelog + SEO).

Tools: Markdown in a `content/` dir of the marketing site, deployed on the same infrastructure.

Goal: 100 posts in year 1. Most will get zero traffic. 5-10 will drive 80% of organic inbound.

### 5. Community presence

Not an original pillar but implicit in the other four. Show up where the audience is:

- YC Slack / Discord
- r/sre, r/devops
- Hacker News — launch post, then feature announcements
- SREcon, DevOpsDays — lurk first, sponsor small meetups year two
- Indie Hackers — build-in-public posts

Budget: 2-4 hours/week of founder time. No paid ads in year 1.

## Product priority — why this order

The sequence below is deliberate. Each feature either unlocks revenue directly or makes the next feature valuable. Shipping out of order wastes effort.

### 1. On-call (months 1-2) — biggest TAM unlock

Without on-call, every prospect asks "what about paging?" and buys PagerDuty as their primary tool. Firefight ends up secondary. With it, Firefight replaces PagerDuty for 10-50 engineer SaaS teams. Roughly **2x acquisition rate** once shipped.

MVP: weekly rotation schedules, two-step escalation (primary → backup), Slack + email notifications, ack/resolve from Slack, "who's on-call" command. SMS + phone (Twilio) come later as paid tier.

### 2. Status pages (month 3) — quick win

Two weeks of work. Kills the "we also need StatusPage.io" objection, gives customers a public artifact that links back to you, bundled-free is a sales weapon.

MVP: public page per workspace (CNAME), component list, incident history, email subscribers. No maintenance windows or uptime SLAs in year 1.

### 3. Ability Gateway + first 3 integrations (months 4-5) — acquisition flywheel

Integrations are SEO gold ("datadog incident management," "sentry on-call") and each launch is a marketing moment. Ship order: **Datadog, Sentry, GitHub** — covers the SMB SaaS stack.

Ability Gateway is the plumbing that makes each new integration cheap to add. Build the plumbing alongside the first three.

### 4. Workflow templates (month 6) — quick value

Not a custom workflow builder (that's phase 2). Ship **toggle-able templates**:
- "Page lead when severity is Critical"
- "Auto-create Zoom bridge for High and above"
- "Post to #exec for Critical"
- "Prompt for postmortem on close"

Templates cover 80% of SMB workflow needs. Visual builder comes later.

### 5. Custom workflow builder (months 7-9) — lock-in play

Full visual builder with triggers + conditions + actions. This is where switching costs kick in — once a customer has 15 custom workflows, they're not leaving. Incident.io's real moat.

Why not first? Workflows need things to trigger and act on. Without on-call + integrations, the action list is tiny (post Slack message, set field). Workflows become valuable only when you have a rich ecosystem to orchestrate.

### 6. Code intelligence, advanced AI (month 10+)

Cool, differentiated, but doesn't close SMB deals. Build it when enterprise prospects start asking for "AI-powered incident insights." Year 2 material.

## 12-month roadmap

| Month | Product | GTM |
|-------|---------|-----|
| **1** | Billing + RBAC + invites + postmortem editor + runbooks. Public launch. | Open source announcement. Hacker News launch. First 10 design partners → first 10 paying customers. |
| **2-3** | On-call MVP (schedules, escalation, Slack notifications). | Content cadence hits 2 posts/week. First SEO traffic arriving. |
| **4** | Status pages + on-call polish (Twilio SMS/phone). | First on-call launch post. PagerDuty comparison content. |
| **5-6** | Ability Gateway + Datadog, Sentry, GitHub integrations. Workflow templates. | 75-100 paying customers. First customer case study. Indie Hackers milestone post. |
| **7-9** | Custom workflow builder. More integrations (Jira, Linear, Zoom). | 150-200 paying customers. Content flywheel compounding. |
| **10-12** | SSO (free, as acquisition play). Analytics/insights. | Year-1 retrospective post. Sponsor one small SRE conference. 200+ paying customers. |

**End-of-year-1 target:** $15-20k MRR, 200+ paying customers.
**End-of-year-2 target:** $50k MRR, 400-600 paying customers.

## Metrics to track (weekly)

- MRR — net new, churn, expansion
- Paying customers — count
- Trial → paid conversion rate
- Organic search traffic to marketing site
- GitHub stars + weekly deltas (open source signal)
- Self-hosted installs (via anonymous telemetry, opt-in)
- NPS after 30 days of active use

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| incident.io undercuts our pricing | Open source is the hedge — they can't copy that |
| On-call takes longer than 6 months | Prioritize relentlessly, cut scope to schedules + basic escalations |
| Content marketing takes 12+ months to compound | Accept this. Start now, no shortcut exists. |
| Enterprise prospects ask for SSO/SAML before we're ready | Build SSO in Q4 and make it free forever. Marketing moat. |
| Small team = support drowning as customers grow | Self-serve docs first. Only email support until 100+ customers. |
| We get stuck at $10-15k MRR | That's probably a sign the beachhead is wrong. Pivot to a vertical (e.g., fintech-focused SOC 2 compliance angle). |

## What we're deliberately not doing

- **Paid ads** — burns cash, doesn't compound
- **Enterprise sales motion** — no BDRs, no SDRs, no outbound in year 1
- **SOC 2 certification** — defer until we have customers requesting it specifically
- **iOS/Android apps** — web + Slack is enough for year 1
- **Mobile push notifications** — Slack handles it
- **Custom contracts / legal review cycles** — standard ToS only until Enterprise tier arrives

## One-line pitch

"Firefight is the open-source incident management platform for growing SaaS teams. Slack-first, transparently priced, self-hostable. Built by engineers who've been paged at 3 AM."
