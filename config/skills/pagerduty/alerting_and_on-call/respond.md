---
name: pagerduty_respond
when: Acknowledging, escalating or reassigning a PagerDuty incident, adding responders to it, or writing a note on it
tools: [browse_incidents, manage_incidents, browse_escalation_policies, browse_users]
references: [oncall/being_oncall.md]
---
1. Read the incident first with `browse_incidents` and its get action, so you act on its current status, assignee and escalation level.
2. Pick the change. Acknowledging stops it paging further while someone works on it. Escalating moves it to a higher level of its escalation policy, read with `browse_escalation_policies`, which pages the people there. Reassigning hands it to a named person, found with `browse_users`. Adding responders asks more people or another escalation policy to join without taking it off whoever has it. Resolving is for a person to decide once the problem is fixed.
3. Tell the person exactly what will change on which incident, then call `manage_incidents`: update for the status, assignee or escalation level, add_responders to bring people in with a message saying why, and add_note to record what is known. The person confirms each call.
4. Read the incident again with `browse_incidents` to confirm the change, and give the person its link.
