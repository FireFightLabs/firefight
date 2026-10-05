---
name: grafana_metrics
when: Reading a service's metrics in Prometheus through Grafana, such as cpu, memory, restarts, request rates or latency, with PromQL
tools: [query_metrics, list_datasources, list_prometheus_metric_names, list_prometheus_label_names, list_prometheus_label_values, query_prometheus, query_prometheus_histogram, search_dashboards, get_dashboard_panel_queries]
references: [guides/query-metrics-with-prometheus.md, guides/search-and-inspect-dashboards.md, reference/mcp-tools-table.md]
---
1. Call `query_metrics` for the service with metrics [cpu, memory]. It reads Kubernetes' cAdvisor metrics by the container's name, cpu in cores and memory in MiB, one series per pod, and each answer is drawn as a chart. Any other metric depends on how the team instruments its code, so find it with the steps below.
2. Call `list_datasources` with type prometheus for the datasource's uid. The team's own dashboard is the quickest way to the right metrics, so call `search_dashboards` with the service's name and `get_dashboard_panel_queries` with its uid, and reuse the queries its panels run.
3. Otherwise call `list_prometheus_metric_names` with a regex, such as http_.*, for the service's metrics, `list_prometheus_label_names` for the labels they carry, and `list_prometheus_label_values` with labelName job, service or container to find the value that is this service.
4. Call `query_prometheus` with queryType range, startTime and endTime such as now-2h and now, and stepSeconds 60. Useful queries, with the service's own labels in place of these:
   - Restarts: increase(kube_pod_container_status_restarts_total{container="checkout"}[1h]), from kube-state-metrics. A container that restarts again and again is crashing.
   - Killed for memory: kube_pod_container_status_last_terminated_reason{container="checkout", reason="OOMKilled"} is 1 for a container whose last exit was running out of memory.
   - Requests and errors: sum by (status) (rate(http_requests_total{job="checkout"}[5m])), when the service exposes a counter of that kind. The names differ between libraries, which step 3 finds.
5. For latency, call `query_prometheus_histogram` with the histogram's base name (without _bucket), percentile 99 and labels such as job="checkout". Compare it over a range that starts well before the problem, to see the minute it rose.
6. Say what the numbers show, from when, and compare them with what is normal for the service on the resource map. Give the person the link to Grafana's Explore that each answer ends with.
