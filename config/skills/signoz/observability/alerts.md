---
name: signoz_alerts
when: Finding why a SigNoz alert fired, whether it is still firing, and what is behind it
tools: [signoz_list_alerts, signoz_get_alert, signoz_get_alert_history, query_metrics, search_errors, search_logs]
references: [alerts/SKILL.md, alerts/baseline-comparison.md, alerts/neighbor-signals.md]
---
1. Call `signoz_list_alerts` for what is firing now, then `signoz_get_alert` with the rule's id for what it measures, its query and its threshold.
2. Call `signoz_get_alert_history` for the rule over a range wider than the incident (6 hours by default). It shows whether it fires often, which makes it background, or began with the problem.
3. Read the same signal the alert measures over the same range, with `query_metrics` for request or error counts, or `search_errors` and `search_logs` for the service behind it. Compare it with the hours before, so a normal daily peak is not taken for the cause.
4. Say what fired, since when, whether it is still firing, and what the signal shows.
