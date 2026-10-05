---
name: grafana_triage
when: Any question about a service Grafana watches, such as why it fails, slows down or restarts, what alerted, or what changed around it
tools: [alerting_rules_read, get_annotations, search_dashboards, get_dashboard_panel_queries, search_logs, query_metrics, search_traces, list_datasources]
references: [guides/manage-alert-rules.md, guides/search-and-inspect-dashboards.md, reference/mcp-tools-table.md]
---
`search_logs`, `query_metrics` and `search_traces` ask Grafana's Loki, Prometheus and Tempo for a service on the resource map by its name, and the platform that runs the service answers its status and deploys. Loki finds the service by its service_name label, Tempo by its service.name, and Prometheus answers only cpu and memory, by the container's name in Kubernetes. When one of them finds nothing, the service is probably labelled another way, and the skills grafana_logs, grafana_metrics and grafana_traces show how to find the right label with Grafana's own tools.

1. Call `alerting_rules_read` with operation list and states [firing, pending] for what is alerting now. A rule's labels and its query say which service and what it measured, and get with its rule_uid shows the full rule and its current alerts.
2. Call `get_annotations` with from and to in epoch milliseconds, over a range that starts well before the problem, for deployments and changes the team marks on its dashboards. A change minutes before the problem began is the first suspect. Annotations are only there when a team's pipeline writes them, so none does not mean nothing changed.
3. Call `search_dashboards` with the service's name for the team's own dashboard, then `get_dashboard_panel_queries` with its uid. The team's panels name the metrics and labels that matter for this service, which saves guessing them.
4. Call `search_logs` for the service with the text of the error, `query_metrics` with metrics [cpu, memory], and `search_traces` for its slowest requests, over the same range. Every answer ends with a link to Grafana's Explore on the same query, so give the person that link with what you found.
5. Then load the skill that fits: grafana_logs for errors and log lines, grafana_metrics for resource use, restarts and rates, grafana_traces for slow or failing requests.
6. When a call says Grafana's datasource for this connection is not known, `list_datasources` shows which Loki, Prometheus and Tempo datasources Grafana has. Firefight reads the one chosen on the connection's details, else the only one of its type, else Grafana's default. Tell the person to switch list_datasources on if it is off, so the health check can find them, and to choose one in Integrations when there are several and none is the default.
