---
name: newrelic_triage
when: Any question about a service New Relic watches, such as why it fails or slows down, what alerted, or what changed around it
tools: [list_recent_issues, search_incident, get_entity, list_related_entities, analyze_golden_metrics, query_metrics, recent_deploys, list_change_events, search_logs]
references: [nrql/SKILL.md]
---
How New Relic is reached: `search_logs`, `query_metrics` and `recent_deploys` ask New Relic for a service on the resource map by the name its agent reports (its APM app name), in the account each environment was connected with. `query_metrics` keeps requests and errors per minute, and the platform that runs the service answers the rest. New Relic's own tools reach every entity in the account, including ones that are not on the map, and most of them take the entity's GUID, which `get_entity` gives.

1. Call `list_recent_issues` for what is open now, and `search_incident` for the alert events that opened and closed around the problem, which say when it began and what was measured.
2. Call `get_entity` for the service by name to get its GUID, then `analyze_golden_metrics` over a range that starts well before the problem. Throughput, response time and error rate together say which kind of trouble it is:
   - Errors rising on flat throughput point at the code or something it calls. Load the newrelic_errors skill.
   - Response time rising points at the code, the database or a service it calls. Load the newrelic_slow_transactions skill.
   - Throughput falling to near zero points upstream, at whatever sends it traffic, or at the agent no longer reporting.
3. Call `recent_deploys` for the deployments and changes New Relic recorded, or `list_change_events` with the GUID for an entity that is not on the map. A change minutes before the problem began is the first suspect.
4. Call `list_related_entities` with the GUID for what the service calls and what calls it. A failing dependency is often the cause of errors in the service that calls it.
5. Read what it logged with `search_logs` around the moment the metrics turned. Logs in context carry the trace id, which links a line to the request that wrote it.

A New Relic answer with nothing in it proves only that nothing matched. A misspelled name, another account, or an agent that never reported all return nothing too, so say which of these you ruled out.
