---
name: posthog_logs_and_traces
when: Reading the logs and traces a backend service sends PostHog, to find when its errors began or where its requests spend their time
tools: [search_logs, search_traces, logs_attribute_values_list, logs_count_ranges, query_logs, apm_services_list, apm_trace_get]
references: [logs/search.md, logs/troubleshooting.md, logs/link-session-replay.md]
---
1. `search_logs` and `search_traces` find a service by the name it has on the map. When PostHog knows it by another name, call `logs_attribute_values_list` with `key` service.name and `attribute_type` resource, or `apm_services_list`, and use PostHog's name with `query_logs`.
2. Call `logs_count_ranges` for the service over the incident and a while before it to see when the volume of error logs changed, then narrow the range to the bucket where it changed.
3. Call `search_logs` for the service over that range with the error's text. A log line carries its trace_id and span_id when the app sends them.
4. Call `search_traces` for the service. It returns the service's slowest spans first, with their status. `apm_trace_get` with a `trace_id` gives the whole request, and the span with the largest self time is where the time went.
5. No logs or traces at all for a service usually means it does not send them to PostHog. Say so and read them from the platform that runs it.
