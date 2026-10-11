---
name: capacity
when: Something is slow or busy, someone asks to scale, a performance regression, a limit or quota close to its ceiling, or spend that moved
tools: [run_key_query, query_metrics, search_logs, resource_status, what_changed, scale]
---
What good looks like: capacity grows ahead of need. Performance regressions are caught and traced to a cause. Spend matches what the system does, and surprises are explained.

How to approach it:
1. Before scaling, know why it is busy. More instances help with real demand. They make things worse when the load is abuse, a retry storm, a slow dependency or a connection limit downstream. Find who generates the load (a client, a key, an endpoint) in the logs before you `scale`.
2. Find the bottleneck: CPU, memory, connections, a lock, a slow query, an external API. Scaling the wrong layer moves the problem.
3. Trace a regression to a change with `what_changed`: a deploy, a config, a step in data growth, a new client.
4. Explain cost from usage: which service, which resource, since when, and what drove it. The cost_trends skill says how to read spend.

What to check:
- Saturation signals for each layer of the request path (`run_key_query`, `query_metrics`).
- Who generates the load: client, key, endpoint.
- What changed when performance or cost moved.
- Limits and quotas close to their ceiling (`resource_status`).

Trade-offs:
- Scaling up is fast and costs money. Fixing the cause is slower and lasts.
- Pausing an expensive resource saves money but may belong to someone. Ask the owner first.

Done means: the system has the headroom it needs, the cause of the change is known, and anyone affected knows what was done and what it costs.

Proactive habits:
- Forecast growth from trends and say when a limit will be reached.
- Notice resources that cost money and serve nothing.
