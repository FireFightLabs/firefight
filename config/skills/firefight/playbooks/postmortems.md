---
name: postmortems
when: Writing or reviewing a postmortem, reconstructing what happened in an incident, turning a lesson into an action or a check, or following up on action items
tools: [get_postmortem, start_postmortem, update_postmortem, get_incident_transcript, create_action_item, search_similar]
---
What good looks like: every significant incident produces a blameless account of how the system allowed the failure, and actions that make the same failure impossible or harmless. Lessons become checks that keep working after people forget.

How to approach it:
1. Reconstruct the timeline from evidence: alerts, changes, what was said in the channel (`get_incident_transcript`) and the steps taken.
2. Ask how, not who. What made the mistake easy? What made it slow to notice? What made it hard to fix?
3. Look for contributing factors rather than one root cause: the change, the missing guard, the missing alert, the unclear runbook.
4. Write actions that change the system: a test, an alert, a guard, an automated check, a runbook update. Each has an owner (`create_action_item`).
5. Turn the lesson into a check that future changes are reviewed against, linked to this incident.

What to check:
- Time to detect, time to mitigate, time to resolve.
- Whether alerts fired, and whether they were the first signal.
- Whether the runbook or the handbook was right.
- Earlier incidents with the same cause (`search_similar`).

Trade-offs:
- Many small actions get lost. Prefer a few that change the system over many reminders.

Done means: the postmortem is written (`start_postmortem`, `update_postmortem`) and shared, its actions have owners, and you follow them until they are finished.

Proactive habits:
- Remind owners of overdue actions.
- Notice repeated incidents with the same cause and say so.
