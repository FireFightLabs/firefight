---
name: tinybird_failing_endpoints
when: A Tinybird API endpoint answers errors, such as 400, 403, 408, 429 or 500 responses, or the app reading it shows nothing
tools: [search_errors, search_logs, query_metrics, endpoint_requests, list_endpoints, call_endpoint, run_query]
---
An endpoint is a published pipe, so its errors come from the request it was sent or from the SQL its nodes run.

1. Call `search_errors` for the endpoint over the window. Each group has the HTTP status Tinybird answered and its error.
2. Read the status first:
   - 400 is the request. A parameter is missing, has the wrong type or is not one the endpoint defines. `list_endpoints` names the parameters each endpoint takes, and which are required.
   - 403 is the token. It has no read scope on this pipe, or it was refreshed or deleted. Compare the token name in `endpoint_requests` with the tokens the team expects.
   - 408 is a query that ran past the plan's limit, 10 seconds on Free and 20 on Developer and SaaS. Load tinybird_slow_endpoints.
   - 429 is a rate limit. When the cluster is under memory or CPU pressure and an endpoint's timeouts and server errors pass 10% of its successful requests, Tinybird's cluster control lowers how many requests it runs at once, and the rest are refused with 429 until the errors stop.
   - 500 is the query failing. Its error names the ClickHouse error, such as MEMORY_LIMIT_EXCEEDED when the query needs more memory than it may use.
3. Call `query_metrics` for the endpoint with `metrics` set to requests, errors, http_4xx and http_5xx, to see when the errors began and whether traffic rose with them.
4. Read single requests with `endpoint_requests` and `failed_only`, with `text` set to the parameter or error the person mentioned. Each line has the address it was called with, the rows read and the time it took.
5. Try the call yourself with `call_endpoint`, using the parameters from a failed request, to see whether it still fails. It counts toward the endpoint's rate limit, so call it once rather than in a loop.
6. For MEMORY_LIMIT_EXCEEDED, look at how much each request read with `run_query` on tinybird.pipe_stats_rt, reading its read_bytes, read_rows and memory_usage columns for the endpoint. A request that reads far more than the others is a filter that does not match the data source's sorting key.

A fix to an endpoint is a change to its pipe that the team deploys. Say what you found and which node it points to, and leave the change to them.
