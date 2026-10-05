---
name: betterstack_triage
when: Any question about something Better Stack monitors, such as whether a site is down, which incident is open, who is on call, or why a service fails
tools: [incidents, incident, incident_timeline, incident_comments, chart_alerts, resource_status, monitor_availability, monitor_response_times, on_calls]
---
How Better Stack is reached: `resource_status` asks the Better Stack monitor that checks a hostname on the resource map, or a hostname the map says a service serves, how it stands. Better Stack's own tools reach every monitor, incident, source and application of the team. When a result links to its page in Better Stack, that link goes in your answer.

1. Call `incidents` with status ongoing and acknowledged for what is open now, or `incident` with an incident's id. Then `incident_timeline` and `incident_comments` for what happened and what people already said, so you do not repeat it.
2. Call `chart_alerts` for the telemetry alerts that are firing.
3. For a monitor that is down, call `resource_status` for the hostname, then `monitor_response_times` and `monitor_availability`. Response times by region tell a full outage from a regional one, or from one that is only slow.
4. Call `on_calls` to say who is on call.
5. Then load the skill that fits: betterstack_logs to read what the service logged, betterstack_errors for the errors it raised. Acknowledging, escalating or resolving an incident is for a person to ask for, never a step to take here.
