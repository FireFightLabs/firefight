---
name: tinybird_slow_endpoints
when: A Tinybird API endpoint is slow, its latency rose, or it times out with 408
tools: [query_metrics, endpoint_metrics, endpoint_requests, resource_status, run_query, list_datasources]
---
Tinybird measures an endpoint's latency as the time from receiving a request to answering it, which pipe_stats_rt keeps as each request's duration.

1. Call `endpoint_metrics` for the endpoint with `metrics` set to requests, latency and cpu_time, over a range that starts well before it slowed. Latency is drawn as its average and its 95th percentile. A 95th percentile that rose while the average did not is a few requests that read much more than the rest.
2. Compare with the same hours on another day with `query_metrics` and `start` and `end`. Latency that rises with requests is load. Latency that rises on its own is the data or the query.
3. Read the slowest requests with `endpoint_requests` for the endpoint. Each line has the milliseconds it took and the rows it read. Requests that read many more rows than they return filter on columns the data source is not sorted by.
4. Call `resource_status` for each data source the endpoint reads, which `list_datasources` names with the pipes that read them. Its sorting key says which filters Tinybird can use to skip data, and its rows say how much there is to scan.
5. To compare requests by parameter, use `run_query` on tinybird.pipe_stats_rt, which keeps each request's parameters in its parameters column, grouped by the parameter and ordered by the average of duration.

A query that runs past the plan's limit fails with 408, 10 seconds on Free and 20 on Developer and SaaS. Only a paid plan can raise it, through Tinybird's support. Making the query read less, with a sorting key that matches its filters or a materialized view that does the work at ingest, is the team's change to deploy.
