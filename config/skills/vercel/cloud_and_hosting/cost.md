---
name: vercel_cost
when: Watching or explaining what the Vercel team spends, a bill that grew, or which service or project costs more than before
tools: [billing_charges, list_resources]
signals: [cost]
---
1. Read this month by day with `billing_charges` and `by` day, then the months before with `by` month and `months` 3.
2. Compare whole days, and the same days of last month. Find the service that grew, such as function duration or data transfer, and the project behind it.
3. For a project that grew, find what changed in it with `list_resources` and its deployments, such as a new function or more traffic.
4. Vercel refusing the read means the token's role on the team cannot see billing. Say so, and that an admin gives the token a role that can.
