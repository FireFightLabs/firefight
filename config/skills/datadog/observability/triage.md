---
name: datadog_triage
when: Any question about a service Datadog watches, such as why it fails or slows down, what alerted, or what changed around it
tools: [search_datadog_monitors, search_datadog_events, search_datadog_entities, search_errors, search_logs, search_datadog_logs]
---
How Datadog is reached: `search_logs`, `search_traces` and `search_errors` ask Datadog for a service on the resource map by its name in Datadog, and the platform that runs the service answers its status and deploys. Datadog's own tools reach every service Datadog sees, by its service tag, including ones that are not on the map. `text` in those three is searched as written, word for word. A filter in Datadog's query syntax, such as service:checkout status:error with - in front to exclude, goes to Datadog's own `search_datadog_logs` or `search_datadog_spans` as their query.

1. Call `search_datadog_monitors` with status alerting for what is firing now and on which service. A monitor's query and threshold say what it measured.
2. Call `search_datadog_entities` for the service when you need its owner or the services it depends on. A failing dependency is often the cause of errors in the service that calls it.
3. Call `search_datadog_events` over a range that starts well before the problem, for deployments, configuration changes and earlier alerts. A change minutes before the problem began is the first suspect.
4. Call `search_errors` for the service to see the grouped errors and when each began, then `search_logs` with the text of the error for its lines. Then load the skill that fits: datadog_errors for failing requests, datadog_latency for slow ones.
