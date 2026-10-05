---
name: railway_failed_to_respond
when: Visitors get a 502, an "Application failed to respond" page, or slow or failing requests from a service on Railway while its deployment is up
tools: [resource_status, search_logs, query_metrics]
references: [networking/application-failed-to-respond.md, deployments/serverless.md, observability/logs.md]
---
Railway's edge proxy answers 502 with "Application failed to respond" when it cannot reach the app behind a public domain.

1. Call `resource_status`. Note its domains and the port each one targets, and whether it sleeps when idle.
2. Call `search_logs` with `stream` requests and `text` 502 over the window. Each request shows its path, status and duration, and why the app did not answer when it did not. Failures on every path point at the app or its port, failures on one path at that route.
3. The common causes, in Railway's words:
   - The app does not listen on host 0.0.0.0 and the PORT variable Railway sets. Read its start lines with `search_logs`, `stream` app, for the address it listens on.
   - A domain's target port is not the port the app listens on.
   - The app is too loaded to answer. Call `query_metrics` with `metrics` cpu, memory and requests and look for a spike at the same time.
4. A service that sleeps when idle wakes on the next request, and that first request can take long or fail with a 502 while it starts.
5. Say which cause it is, with the request lines that show it. A wrong port or listen address is a change to the service's settings or code for a person to make, so name the setting and the value.
