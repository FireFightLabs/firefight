---
name: monitoring
when: Judging whether a service is healthy or an alert is real, comparing a signal with normal, finding blind spots or noisy alerts, or telling a provider's outage from your own
tools: [run_key_query, new_log_patterns, query_metrics, search_logs, check_status_page, blind_spots, check_from_outside]
---
What good looks like: you know each service's normal and notice when it moves. Alerts are rare, real and actionable. There are no blind spots on the paths customers use.

How to approach it:
1. Start from the customer's view. Is the key action working (pages load, checkout completes, email sends)? `check_from_outside` checks an address as a user reaches it when that matters.
2. Compare with normal, not with zero. `run_key_query` reads a resource's key checks against its last week. `new_log_patterns` says which kinds of log line are new and which error patterns are usual, so an error printed every day is not taken for the cause unless something shows it changed.
3. Read the alert's own query to judge whether it is real: what it measures, its threshold, and whether the data behind it is fresh.
4. Check freshness before trusting a number. A dashboard can show a calm metric that stopped updating an hour ago.
5. Correlate across signals: a latency spike with a deploy, an error burst with a dependency outage, a traffic jump with one client. When errors point outside, such as timeouts or 5xx answers from a third party's host, `check_status_page` reads that provider's status before you blame the team's code. When a question needs a system nothing connects, `blind_spots` names it and how to connect it, rather than a guess at what it did.

What to check:
- The golden signals for the service: traffic, errors, latency, saturation (`query_metrics`, `search_logs`).
- When each data source last reported.
- New log patterns since the last good period.
- Provider status pages for dependencies.

Trade-offs:
- A noisy alert costs attention every time. Propose fixing or muting it, with an expiry, rather than ignoring it.
- More telemetry is not always better. Add what answers a question you could not answer.

Done means: you can say what is happening, how you know, and whether it is getting better or worse. Noise you found is reported with a proposed fix.

Proactive habits:
- Watch trends that will become alerts: growing error rates, disks filling, queues backing up. The disk_trends, certificate_expiry and error_budget_burn skills say how to read each.
- Point out blind spots: a path with no logs, a service with no health check, a dependency nobody watches.
