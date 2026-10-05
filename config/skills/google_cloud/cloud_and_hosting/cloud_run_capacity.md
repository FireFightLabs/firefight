---
name: google_cloud_cloud_run_capacity
when: A Cloud Run service is slow, answers 429 or 500 "no available instance", or cannot keep up with its traffic
tools: [query_metrics, resource_status, search_logs, scale]
references: [run/troubleshooting.md, run/min-instances.md, run/max-instances.md, run/monitoring.md]
---
1. Call `resource_status` for the service's instance limits: the fewest instances it keeps and the most it may start.
2. Call `query_metrics` with `metrics` requests, cpu and memory over the window. cpu and memory are those of its busiest instances.
3. Tell the cause from Cloud Run's message in `search_logs`:
   - 429 "The request was aborted because there was no available instance": the service reached the most instances it may start. Raising that limit lets it start more, unless the project's quota is the limit.
   - 500 "The request was aborted because there was no available instance" before the limit: traffic rose faster than instances could start, usually from a sudden spike, a slow start or slower requests. Keeping more instances warm helps.
   - High latency while CPU is low: requests wait for something outside, or instances are starting cold.
4. To keep instances warm, offer `scale` with `instances` set to the fewest it should keep running. This sets the service's minimum on the service itself, which needs no new revision and is billed while they run. The most it may start is changed in the console. Say the current values, so the undo is setting them back.
5. Say what limited it, the evidence from the metrics, and the change.
