---
name: newrelic_errors
when: Finding why a service New Relic watches returns errors, throws exceptions or fails requests
tools: [list_entity_error_groups, get_error_statistics, execute_nrql_query, get_distributed_trace_details, analyze_entity_logs, search_logs]
references: [errors/SKILL.md, errors/queries.md, traces/SKILL.md]
---
1. Call `list_entity_error_groups` for the service over a range that starts well before the errors. Errors Inbox puts every occurrence that shares a fingerprint in one group, so each group is one kind of error.
2. Call `get_error_statistics` for the service over the same range, broken out over time and by error class, message or HTTP status. It gives each kind its first and last time seen. A kind first seen when the trouble began is new, and one seen for weeks is background.
3. When you need the occurrences themselves, call `execute_nrql_query` on TransactionError for the service's appName, faceted by error.class and error.message, with a LIMIT (a FACET returns only 10 groups without one). Take a trace.id from a recent occurrence.
4. Call `get_distributed_trace_details` for that trace. The span that failed first, and the one that took longest, show whether the error began in the service or in a database or another service it called.
5. Call `analyze_entity_logs` or `search_logs` with the error's text for the lines around it.

Expected errors are marked so they do not count toward the error rate, so an error group can be busy while the rate stays flat.
