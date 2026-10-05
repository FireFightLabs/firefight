---
name: betterstack_logs
when: Reading or counting the logs or spans a service sends to Better Stack, around an incident or an error
tools: [sources, source, source_fields, query_help, query_windows, query, metrics_schema, metrics_query_help]
---
1. Call `sources` to find the source that holds the service's logs, then `source` for its details and `source_fields` for the fields its logs carry.
2. Before writing any SQL, call `query_help` with source_type logs, or spans for traces. Better Stack's SQL is ClickHouse, and the help says how this team's tables and fields are named. A query written without it fails.
3. Run the query with `query`, always bounded in time. Call `query_windows` first when the range is more than a few hours, and query each window it gives.
4. Count before you read. Count lines by level per minute to find when errors began, and group by message to see which are new. Read the lines around the first errors only then.
5. A filter on level or service that finds nothing may only mean those logs do not carry that field. Try without it before saying there are no errors.
6. For metrics, find the metric with `metrics_schema`, then `metrics_query_help` before querying it with `query`.
