---
name: northflank_errors
when: Finding why a service on Northflank returns errors, fails requests or crashes
tools: [list_resources, query_metrics, recent_builds, search_logs]
---
1. Call `list_resources` for the service's exact name and whether it is running, deploying or failed.
2. Call `query_metrics` on that `resource` with `metrics` http5xxResponses and requests, over a range that starts before the trouble. It shows when the errors began and whether they follow traffic.
3. Call `recent_builds` for the same `resource`. A build that finished just before the errors began is the first suspect.
4. Read what the app printed with `search_logs`: `type` runtime, a `regex` for the words it prints when something fails, such as error, exception or fatal, and `start` and `end` around when the errors began. `type` ingress shows the requests that reached it.
5. At most 200 lines come back. When the result says older lines were left out, narrow the range rather than reading the lines as all there were.
