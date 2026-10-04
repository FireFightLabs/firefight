---
name: mixpanel_triage
when: Any question about how an incident shows in Mixpanel, such as how many users it reaches, which events dropped, or which feature flag changed around it
tools: [get_projects, get_business_context, get_events, get_issues, run_query, get_audit_log, list_feature_flags]
references: [metrics/SKILL.md, reports/read-insights.md]
---
How Mixpanel is reached: the connection signs in as one Mixpanel user and sees the projects that user can open. Every Mixpanel tool works on one project, so find it first. Mixpanel allows 600 MCP requests an hour per user, so ask for what answers the question rather than everything.

1. Call `get_projects` and pick the project the incident is in. When the person did not say, ask rather than guess. `get_business_context` gives the team's own words for its events and metrics, which tells you what an event name means.
2. Call `get_events` for the events that stand for the broken step. Never guess an event name, since names differ between projects.
3. Call `get_issues` for those events. A data quality issue around the incident, such as a property that changed type or stopped arriving, means the numbers may be wrong rather than the product.
4. Call `run_query` for the event's daily active users by hour over the last seven days. Where it bent, and by how much against the same hour on other days, is the incident's reach. Load mixpanel_user_impact to break it down.
5. Look for what changed. `get_audit_log` lists who changed what and when, and needs an organization admin or owner. `list_feature_flags` shows the project's flags. A change shortly before the problem began is the first suspect. Load mixpanel_feature_flags.
