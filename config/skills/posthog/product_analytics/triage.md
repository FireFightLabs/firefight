---
name: posthog_triage
when: Any question about how an incident shows in PostHog, such as how many users it reaches, what errors they hit, or which feature flag changed around it
tools: [projects_get, switch_project, health_issues_list, query_trends, query_error_tracking_issues_list, advanced_activity_logs_list, annotations_list, search_logs, search_traces]
references: [error-tracking/monitoring.md, logs/start-here.md]
---
How PostHog is reached: a connection reads one PostHog project at a time, its active project. `search_logs` and `search_traces` ask PostHog for a service on the resource map by its name, which is the service.name the app sends PostHog over OpenTelemetry. PostHog's own tools reach the whole project, including services and events that are not on the map. Every PostHog tool takes its time as a `dateRange` with `date_from` and `date_to`, either ISO 8601 or relative to now, such as -6h or -7d.

1. Call `projects_get` for the projects the connection can reach. When the incident is in a project other than the active one, `switch_project` moves to it. PostHog keeps the active project for the connection, so it moves every later call on this connection, in every chat, until it is switched back. PostHog counts it as a change, so the person confirms it, and an investigation cannot make it.
2. Call `health_issues_list` for active issues, such as ingestion warnings or an outdated SDK. A drop in events while PostHog itself reports missing data is an instrumentation problem, not fewer users.
3. Call `query_trends` for the event the incident touches over a range that starts well before it, by `hour`, with `math` dau for people rather than events. Where it bent, and by how much against the same hours a week earlier, is the incident's reach. Load posthog_user_impact to break it down.
4. Call `query_error_tracking_issues_list` over the incident window for errors that began with it, then load posthog_errors.
5. Call `advanced_activity_logs_list` with `scopes` FeatureFlag and a `start_date` well before the incident for flags changed around it, and `annotations_list` for deploys the team marked. A change minutes before the problem began is the first suspect. Load posthog_feature_flags.
6. For a backend service, `search_logs` and `search_traces` read what PostHog holds for it. Load posthog_logs_and_traces.
