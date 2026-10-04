---
name: grafana_traces
when: Finding why requests through a service Grafana watches are slow or fail, from its traces in Tempo with TraceQL
tools: [search_traces, list_datasources, list_tempo_attribute_values, search_tempo_traces, get_tempo_trace, query_tempo_metrics]
references: [reference/mcp-tools-table.md]
---
1. Call `search_traces` for the service over a range that starts well before the problem. It reads Tempo for spans whose resource.service.name is the service, slowest first.
2. When it finds nothing, call `list_datasources` with type tempo for the datasource's uid, then `list_tempo_attribute_values` with name resource.service.name to find the name the service sends its traces under.
3. Call `search_tempo_traces` with a TraceQL query for the requests that matter, with start and end in RFC 3339:
   - Failing: { resource.service.name = "checkout" && status = error }
   - Server errors: { resource.service.name = "checkout" && span.http.status_code >= 500 }
   - Slow: { resource.service.name = "checkout" && duration > 2s }
   - One route: { resource.service.name = "checkout" && name = "POST /api/orders" }
4. Call `get_tempo_trace` with the trace_id of one of them. The longest span in it is where the time went, and a failing span names the call that failed, such as a database or another service.
5. To see when it began, call `query_tempo_metrics` with a TraceQL metrics query and type range, such as { resource.service.name = "checkout" } | quantile_over_time(span:duration, .99) by (span.name) for latency, or { resource.service.name = "checkout" && status = error } | rate() for errors. An instant query over more than about 15 minutes can time out, so read longer ranges as a range.
6. Say which requests, through which calls, and since when, and give the person the link to Grafana's Explore that each answer ends with.
