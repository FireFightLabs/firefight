---
name: azure_cost
when: Watching or explaining what an Azure subscription spends, a bill that grew, or which service costs more than before
tools: [cost_query, list_resources]
signals: [cost]
---
1. Read this month by day with `cost_query` and `by` day, then the months before with `by` month and `months` 3. A connection that reads several subscriptions answers for each.
2. Compare whole days, and the same days of last month, since recent days can still be counting.
3. Find the service that grew and the day it started, then what runs in it with `list_resources`: a new or larger app plan, more Container App replicas, a larger database.
4. Azure refusing the read means the service principal lacks the Cost Management Reader role on the subscription. Say so, and that an admin gives it that role.
