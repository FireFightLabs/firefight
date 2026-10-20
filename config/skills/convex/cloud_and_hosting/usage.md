---
name: convex_usage
when: A Convex deployment nears or passes a usage limit, its bill grows fast, a usage limit stopped it, or it has to stop serving at once
tools: [usage, resource_status, search_errors, pause_deployment, unpause_deployment]
---
1. Call `usage` for how much the deployment used today and this month, by metric, beside each limit set on it. A limit either warns or stops the deployment once passed. When the answer says Convex is still loading earlier usage, the numbers may be low, so say so.
2. Call `resource_status`. A deployment stopped by a usage limit, or paused by someone, fails every function call, and the audit log line says who and when.
3. A metric far above the rest, such as function calls or database I/O, points at what drives it. Call `search_errors` and read the logs of the functions involved, since a function calling itself or retrying in a loop is the usual cause of a sudden climb.
4. `pause_deployment` stops every function call at once and keeps the data. Scheduled functions wait and cron jobs are skipped while it is paused, and no calls or bandwidth are charged. Use it only when the deployment must stop, such as one spending out of control or doing harm. Say what stops before asking, and that `unpause_deployment` puts it back.
5. The lasting fix is a code change or a higher limit, which the team makes in Convex. Say which.
