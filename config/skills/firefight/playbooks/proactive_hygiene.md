---
name: proactive_hygiene
when: Looking ahead for what will break, such as expiring certificates, keys or quotas, trends that will cross a limit, risky changes before they ship, stale runbooks or handbook pages, or repeated manual work
tools: [list_notices, find_resources, check_from_outside, search_runbooks, list_handbook_pages]
---
What good looks like: problems are found before customers find them. Expiring things are renewed in time. Repeated manual work becomes automatic. Documentation matches reality.

How to approach it:
1. Look ahead: certificates, keys, tokens, domains, quotas, budgets and plans that expire or run out. `check_from_outside` reads a certificate as users are served it, and `list_notices` says what was raised before and whether it got worse.
2. Watch trends: error rates, latency, disk, queue depth, cost. A trend needs more than one reading, so read the same measure over days or weeks, work out its rate, and from the rate the day it crosses the line that matters. Say how sure the date is when the rate is uneven.
3. Review risky changes before they ship: migrations on large tables, changes to services with recent incidents, config that affects many services.
4. Test recovery: that a backup restores, that a rollback works, that a failover happens.
5. Keep knowledge true. When a runbook (`search_runbooks`) or a handbook page (`list_handbook_pages`) is wrong, propose the edit, with propose_handbook_edit for the handbook.
6. Reduce toil. When the same manual step happens again and again, propose automating it, or saving it as a runbook.

What to check:
- Expiry dates and remaining quotas.
- Trends against limits, across everything that holds them (`find_resources`).
- Blind spots in monitoring.
- Stale runbooks and handbook pages.

Trade-offs:
- Not every trend needs action now. Say when it will matter and propose a check, rather than raising an alarm.

Done means: each finding is reported with a clear date or threshold, a proposed action and an owner, or fixed when it is safe and allowed.

The certificate_expiry, disk_trends, error_budget_burn and cost_trends skills give the steps for those checks.

Proactive habits:
- This whole playbook is the habit: notice, propose, follow through.
