---
name: pagerduty_triage
when: Finding out what PagerDuty is paging about, what an incident in PagerDuty holds, or what changed on a service before it was paged
tools: [browse_incidents, browse_services, browse_change_events, browse_activity]
references: [oncall/alerting_principles.md]
---
1. Call `browse_incidents` with its list action for the incidents open now, triggered and acknowledged, newest first. Each one names its service, urgency, priority and who it is assigned to.
2. For the incident in question, `browse_incidents` with get reads it in full, list_alerts gives the alerts grouped into it, and list_notes what responders wrote. An incident grouping many alerts from different services points at something they share.
3. Look at what changed before it began: `browse_incidents` with list_change_events gives the changes PagerDuty tied to the incident, and `browse_change_events` with list_service the changes sent for its service, such as deploys. A change minutes before the first alert is the first suspect.
4. `browse_incidents` with context and related shows other incidents open now that may share the cause, and with past the earlier incidents like it and how they ended.
5. When the service matters, `browse_services` with get gives its escalation policy and teams, and `browse_activity` with list_log_entries what happened to the incident so far: who was notified, who acknowledged it, and when.
6. Give the person what is paging, since when, on which service, and each incident's PagerDuty link.
