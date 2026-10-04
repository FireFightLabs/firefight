---
name: datadog_errors
when: Finding why a service Datadog watches returns errors, throws exceptions or fails requests
tools: [search_errors, get_datadog_error_tracking_issue, search_logs, analyze_datadog_logs, search_datadog_spans, get_datadog_trace]
---
1. Call `search_errors` for the service over a range that starts well before the errors. Each issue groups one kind of error with its first and last time seen. An issue first seen when the errors began is new, and one seen for weeks is background.
2. Call `get_datadog_error_tracking_issue` for the issue that began with the problem. Its stack trace names the file and line, and its counts show whether it is spreading.
3. Call `analyze_datadog_logs` to count errors by minute, or by endpoint, host or version, so you can see when they began and whether one version or host has them alone. Errors on one version only point at a deployment.
4. Call `search_logs` with the error's text for the lines around it, and `search_datadog_spans` with the query service:<the service> status:error for failing requests. Then `get_datadog_trace` for one of them shows which call in the request failed, such as a database or another service.
