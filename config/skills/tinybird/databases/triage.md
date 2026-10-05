---
name: tinybird_triage
when: Starting on anything wrong with a Tinybird workspace, such as API endpoints failing or slow, data arriving late or missing, or a deployment gone wrong, before knowing what kind of problem it is
tools: [resource_status, search_errors, query_metrics, search_logs, recent_deploys, list_endpoints, list_datasources]
---
Every Tinybird tool here only reads, so each is safe to call. The workspace, its data sources and its API endpoints are on the resource map, and each capability takes one of them by its name. What they read comes from Tinybird's service data sources, the tables Tinybird keeps about the workspace's own requests, operations and jobs.

1. Call `resource_status` for the workspace. It says how many requests the endpoints answered in the last hour and how many failed, which data sources had operations fail, and the latest deployments. A deployment still waiting or working is a change in progress.
2. When the person named an endpoint or a data source, call `resource_status` for it too. When they did not, `list_endpoints` and `list_datasources` name them.
3. Call `search_errors` over a range that starts before the trouble. Failed endpoint requests, failed data source operations and failed jobs come grouped by what failed and why, so the largest group is usually the problem.
4. Call `recent_deploys`. A deployment that went live shortly before the trouble began is the first suspect, so load tinybird_deployments.
5. Then load the skill that fits: tinybird_failing_endpoints when endpoints answer errors, tinybird_slow_endpoints when they are slow or time out, and tinybird_ingestion when data is late, missing or lands in quarantine.

Tinybird keeps endpoint requests for three months and failed endpoint requests for 30 days, so an older range comes back empty without meaning nothing happened.
