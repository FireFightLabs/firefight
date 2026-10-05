---
name: datadog_latency
when: Finding why a service Datadog watches is slow, times out, or its latency rose
tools: [search_datadog_spans, get_datadog_trace, get_datadog_metric, search_datadog_events, search_logs]
---
1. Call `get_datadog_metric` for the service's request latency, such as trace.http.request.duration grouped by resource_name, over a range that starts well before it slowed. Find the minute it began and whether every endpoint slowed or one.
   - Every endpoint slowing together points at something they share: the host, a database, or load.
   - One endpoint slowing alone points at its own code or what it calls.
2. Call `search_datadog_spans` with a query for the slow endpoint and its duration, such as service:checkout resource_name:"GET /cart" @duration:>2s, then `get_datadog_trace` for one of them. The longest span in it is where the time went.
3. Call `search_datadog_events` around the minute it began for deployments and configuration changes, and `search_logs` with timeout for calls that gave up.
