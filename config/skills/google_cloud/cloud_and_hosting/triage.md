---
name: google_cloud_triage
when: Starting on anything wrong with a Cloud Run service, Cloud SQL instance, Compute Engine instance or GKE cluster on Google Cloud, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, search_errors, search_logs]
references: [run/troubleshooting.md, run/monitoring.md, run/logging.md, logging/logging-query-language.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name and kind. A Cloud Run service shows whether its latest revision is ready, failed or still rolling out. A Cloud SQL or Compute Engine instance shows its state, such as runnable, maintenance, suspended, stopped or terminated.
2. Call `resource_status` on it. For a Cloud Run service, read which revisions serve the traffic and in what share, the image, and its instance limits, since later steps lean on them. A ready condition that failed carries Google's own message about why.
3. For a Cloud Run service, call `recent_deploys`. A revision made shortly before the trouble began is the first suspect, so load the google_cloud_cloud_run_errors skill. A newest revision that is not ready means the deploy itself failed, so load google_cloud_cloud_run_startup.
4. Call `query_metrics` for the window: requests and http_5xx for a service, cpu, memory and disk for a database, cpu for an instance. Errors that rise with requests point at load, so load google_cloud_cloud_run_capacity. Errors on flat traffic point at the code or something it calls.
5. Call `search_errors` on a Cloud Run service for the errors Error Reporting grouped, with how often each happened and when it began.
6. Read what it printed with `search_logs` around the moment the metrics turned. For a Cloud Run service, stream requests lists each request with its status and latency, and the app stream is what the code printed, including Cloud Run's own messages about instances.

For a database, load google_cloud_cloud_sql. For a Compute Engine instance, load google_cloud_compute. For a GKE cluster, load google_cloud_gke. Cloud Monitoring keeps a minute per point at best, so a spike of a few seconds may only show as a small rise.
