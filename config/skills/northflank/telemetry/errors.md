---
name: northflank_errors
when: Finding why a service on Northflank returns 5xx errors, times out or fails requests
tools: [describe_resource, query_metrics, list_deployments, list_containers, search_logs]
---
1. Call `describe_resource` for the service. Note its health checks and ports. A readiness probe that keeps failing takes a container out of traffic, and with one instance that is every request.
2. Call `query_metrics` with `metrics` http5xxResponses, http4xxResponses and requests, over a range that starts well before the errors. Find the minute they began.
   - 5xx rising together with requests, with cpu or memory near the top, is load. Check instances in `describe_resource` and the northflank_resources skill.
   - 5xx on steady traffic is the code or something it depends on, such as a database or another service.
   - 4xx rising alone is usually callers sending bad requests or failing authentication, not the service breaking.
3. Call `list_deployments`. A deployment within minutes before the errors began is the first suspect, and its commit is where to look in the code.
4. Call `list_containers`. Containers restarting during the errors mean crashes, so load the northflank_crashes skill.
5. Read the failures with `search_logs`:
   - `type` runtime with a `regex` for what the app prints when a request fails, such as error|exception|fatal|timeout, and `start` and `end` around the first minute of errors.
   - `type` ingress for the requests that reached the service, to see which paths fail.
   - `type` mesh when this service calls another one inside Northflank and those calls fail.
   At most 200 lines come back. When the result says older lines were left out, narrow the range instead of reading those lines as all there were.
6. Say which requests fail, since when, and the evidence for why: the log lines, the deployment, or the load.
