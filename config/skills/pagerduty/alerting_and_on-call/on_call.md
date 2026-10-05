---
name: pagerduty_on_call
when: Finding who is on call in PagerDuty, who an incident or service pages next, or who to bring in from another team
tools: [browse_schedules, browse_escalation_policies, browse_services, browse_teams, browse_users]
references: [oncall/being_oncall.md, oncall/whos_oncall.md]
---
1. For who is on call now, call `browse_schedules` with list_oncalls. Each entry names the person, the schedule and escalation policy that put them there, and the escalation level, where level 1 is paged first.
2. For one service, `browse_services` with get gives its escalation policy, and `browse_escalation_policies` with get gives each level in order, who it notifies and after how many minutes an unacknowledged incident moves on.
3. For a schedule over a time, `browse_schedules` with get or list_users shows who covers it.
4. To find someone on another team, `browse_teams` with list_members, then `browse_users` with get for how to reach them.
5. Name the person on call first, then who comes next and when, with their PagerDuty links. An on-call engineer is the first to triage their service, and anyone can escalate when the problem is not theirs to fix.
