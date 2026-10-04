---
name: logfire_slow_requests
when: Finding why a service that sends to Logfire is slow, times out, or its latency rose
tools: [search_traces, query_run, query_metrics, project_logfire_link]
references: [query/SKILL.md, query/schema.md]
---
1. Call `search_traces` for the service to find its slowest spans and their trace ids.
2. Find when it slowed with `query_run`: the approx_percentile_cont of duration at 0.5 and 0.99 per time_bucket of 5 minutes, for the service's spans with an http_route, grouped by http_route. duration is in seconds.
   - Every route slowing together points at something they share: a database, a dependency, or the cpu, which `query_metrics` shows.
   - One route slowing alone points at its own code or what it calls.
3. Read the slowest trace with `query_run` WHERE trace_id = 'the id' ORDER BY start_timestamp. The span with most of the time, or many short spans one after another, is where it went.
4. `project_logfire_link` with the trace id gives its page in Logfire for your answer.
