---
name: grafana_logs
when: Finding why a service Grafana watches logs errors, or reading its log lines in Loki with LogQL
tools: [search_logs, list_datasources, list_loki_label_names, list_loki_label_values, query_loki_stats, query_loki_logs, query_loki_patterns]
references: [guides/query-logs-with-loki.md, reference/mcp-tools-table.md]
---
1. Call `search_logs` for the service with the error's text. It reads Loki through the stream selector {service_name="<the service>"}, newest first.
2. When it finds nothing, find how the service is labelled. Call `list_datasources` with type loki for the datasource's uid, then `list_loki_label_names` with that datasourceUid. Loki fills service_name from labels such as service, app, application, container or job, so call `list_loki_label_values` with labelName service_name, then app or job, to find the value that is this service.
3. Before a wide search, call `query_loki_stats` with the stream selector alone, such as {app="checkout"}. It says how many streams and bytes the range holds, so a query that would read gigabytes is narrowed first.
4. Call `query_loki_logs` with a LogQL query, the selector first and filters after it, newest first by default:
   - {app="checkout"} |= "timeout" keeps lines containing timeout, and != "healthcheck" drops lines containing healthcheck.
   - {app="checkout"} |~ "(?i)error|exception" keeps lines matching a regular expression.
   - {app="checkout"} | json | status >= 500 parses JSON lines and keeps those whose status field is 500 or more. Use | logfmt for key=value lines.
   Give startRfc3339 and endRfc3339 explicitly, such as now-2h and now, since the tool reads only the last hour by default, and set limit, since it returns 10 lines unless asked for more.
5. To see when errors began, call `query_loki_logs` with a metric query and queryType range, such as sum(count_over_time({app="checkout"} |= "error" [5m])), with stepSeconds 300. The first step where the count rises is when it began.
6. Call `query_loki_patterns` with the stream selector to group lines into patterns with how often each was seen. A pattern that appears only since the problem began is the new error, and one seen all along is background.
7. Say which lines, from when, and how many, and give the person the link to Grafana's Explore that each answer ends with.
