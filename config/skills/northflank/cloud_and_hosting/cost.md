---
name: northflank_cost
when: Watching or explaining what the Northflank account or team spends, a bill that grew, or which kind of charge costs more than before
tools: [billing_usage, list_resources]
signals: [cost]
---
1. Read this month by day with `billing_usage` and `by` day, then the months before with `by` month and `months` 3.
2. Compare whole days, and the same days of last month. Find the charge that grew, CPU, memory, storage, GPU, bring your own cloud, egress IPs or load balancers, and the day it started.
3. For compute that grew, find what runs with `list_resources`: more instances, a larger plan, or a new service or job.
4. Northflank refusing the read means the token's role cannot read billing. Say so, and that an admin adds Billing read to it.
