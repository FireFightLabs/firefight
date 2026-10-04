---
name: logfire_triage
when: Any question about a service that sends its logs and traces to Pydantic Logfire, such as why it fails or slows down, or what it did around a time
tools: [search_errors, search_logs, search_traces, query_metrics, query_run, query_schema_reference, project_logfire_link]
references: [query/SKILL.md, query/schema.md]
---
How Logfire is reached: `search_logs`, `search_traces`, `search_errors` and `query_metrics` ask Logfire for a service on the resource map by its service_name, and link to Logfire's live view of the same service and time. `query_run` runs any SQL on the records and metrics tables, including services that are not on the map.

1. Call `search_errors` for the service over a range that starts well before the problem. Each kind of exception comes with how often and when it was first and last seen, so one that began with the problem stands out.
2. Call `query_metrics` with requests and http_5xx to see when the failures began and whether traffic changed, and cpu when the service was slow.
3. Call `search_logs` with the text of an error for the lines around it, and `search_traces` for the failed and slowest spans.
4. For anything else, write SQL for `query_run`. It always needs a LIMIT, reads at most 14 days, and takes the range as min_timestamp and max_timestamp. `query_schema_reference` gives the columns. service_name, span_name, trace_id and is_exception are the fast filters.
5. Then load the skill that fits: logfire_exceptions for errors, logfire_slow_requests for slow ones. `project_logfire_link` with a trace id gives the trace's page in Logfire, which goes in your answer.
