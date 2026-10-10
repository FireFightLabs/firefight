---
name: error_budget_burn
when: A scheduled check of error budgets, or anyone asking whether a service is failing more than its objective allows and when its budget runs out
tools: [list_notices, find_resources, get_resource, query_metrics, search_errors]
---
1. The objective comes from the check's notes or the team's instructions, such as 99.9% of requests succeed over 30 days. Without one, use 99.9% over 30 days and say so.
2. List the services the check covers with `find_resources`, passing `kind` service and function, or the `catalog_entry` or `owner` the notes name.
3. For each, read requests and errors with `query_metrics`, passing `metrics` requests, errors and http_5xx, over the last 30 days (`minutes` 43200), and again over the last day.
4. The budget is the share of requests the objective lets fail. The burn rate is the share failing divided by that budget. A burn rate of 1 spends the budget exactly over the window. Work out how much of the budget the window has spent so far, and at the last day's rate the day it runs out.
5. Raise a service whose budget runs out before the window ends: medium when it lasts more than a week, high when it runs out within a week or the last day burned faster than 6. Name the errors behind it with `search_errors`.
6. Read `list_notices` with `signal` error_budget first, and keep the topic and resource of anything raised before.
7. A service with no request or error metric is a gap to say, naming what would read it.
