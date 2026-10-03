---
name: northflank_errors
when: Finding why a service on Northflank returns 5xx errors, times out or fails requests
tools: [resource_status, query_metrics, recent_deploys, list_containers, search_logs]
---
1. Call `resource_status` for the service. Note its health checks and ports. A readiness probe that keeps failing takes a container out of traffic, and with one instance that is every request.
2. Call `query_metrics` with `metrics` http_5xx, http_4xx and requests, over a range that starts well before the errors. Find the minute they began.
   - 5xx rising together with requests, with cpu or memory near the top, is load. Check instances in `resource_status` and the northflank_resources skill.
   - 5xx on steady traffic is the code or something it depends on, such as a database or another service.
   - 4xx rising alone is usually callers sending bad requests or failing authentication, not the service breaking.
   - When requests, 4xx and 5xx come back with no data, that does not show there was no traffic, and Northflank may not record HTTP metrics for this service. Ask `query_metrics` for network_in in its `metrics` for traffic, and `search_logs` with `stream` app for each request's path and status.
3. Call `recent_deploys`. A deployment within minutes before the errors began is the first suspect, and its commit is where to look in the code.
4. Call `list_containers`. Containers restarting during the errors mean crashes, so load the northflank_crashes skill.
5. Read the failures with `search_logs`:
   - `stream` app with a `regex` for what the app prints when a request fails, such as error|exception|fatal|timeout, and `start` and `end` around the first minute of errors.
   - `stream` requests for the requests that reached the service, to see which paths fail. Northflank has ingress logs only where it switched them on for the account. When the result says they are not switched on, read `stream` app instead, since the app usually logs each request's path and status there.
   - `stream` internal when this service calls another one inside Northflank and those calls fail.
   At most 200 lines come back. When the result says older lines were left out, narrow the range instead of reading those lines as all there were.
6. Say which requests fail, since when, and the evidence for why: the log lines, the deployment, or the load.
