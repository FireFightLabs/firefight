---
name: render_http_errors
when: Visitors get 5xx errors, such as 500 or 502, or slow responses, from a web service on Render
tools: [query_metrics, search_logs, list_events, resource_status, recent_deploys]
references: [debug/error-patterns.md, debug/log-analysis.md, debug/troubleshooting.md]
---
1. Call `query_metrics` with `metrics` requests, http_5xx and http_4xx for the window. The 5xx series adds up every 5xx code, so read the request logs in step 3 for which ones.
2. Separate the two common causes:
   - 502 comes from Render's proxy when it cannot get an answer from the app: an app not listening on 0.0.0.0 at the PORT variable, an instance restarting or crashing (step 4), keep-alive or header timeouts in Node that are shorter than the proxy's, or worker timeouts that kill requests, such as gunicorn's WORKER TIMEOUT.
   - 500 comes from the app itself: an uncaught exception, a database it cannot reach, or an instance out of CPU, memory or connections.
3. Call `search_logs` with `stream` requests and `regex` 5.. to see which paths and codes fail. Request logs exist only on Pro workspaces and higher, and only for traffic from the internet. Without them, search `stream` app with `text` set to error or the path.
4. Call `list_events` for the window. Failed or restarted instances during the errors mean the errors are a symptom, so load the render_crashes skill.
5. Call `recent_deploys`. Errors that began with a deploy point at that change.
6. Call `query_metrics` with `metrics` cpu and memory. Errors that rise with traffic while cpu sits at its limit mean the service needs more instances, which the render_fixes skill covers.
