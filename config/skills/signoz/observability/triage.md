---
name: signoz_triage
when: Any question about a service SigNoz watches, such as why it fails or slows down, which alert fired, or what changed around it
tools: [signoz_list_alerts, signoz_list_services, signoz_get_service_top_operations, search_errors, search_logs, search_traces, query_metrics]
references: [alerts/SKILL.md, alerts/neighbor-signals.md, queries/SKILL.md]
---
How SigNoz is reached: `search_logs`, `search_traces`, `search_errors` and `query_metrics` ask SigNoz for a service on the resource map by its service.name. SigNoz's own tools reach every service it sees, including ones that are not on the map. Spans and traces carry their page in SigNoz, and counts link to the service's page, which goes in your answer.

1. Call `signoz_list_alerts` for the alerts firing now, and load signoz_alerts when one of them is the question.
2. Call `signoz_list_services` for the services SigNoz saw in the range, to find the one the question is about by its name in SigNoz.
3. Call `query_metrics` with requests and errors for the service over a range that starts well before the problem, to find the minute it began.
4. Call `search_errors` for the operations whose spans failed, and `signoz_get_service_top_operations` for the operations ranked by their slowest calls.
5. Call `search_logs` with the text of an error for the lines around it, and `search_traces` for the failed and slowest spans. Then load the skill that fits: signoz_latency for slow requests, signoz_logs to dig through logs.
