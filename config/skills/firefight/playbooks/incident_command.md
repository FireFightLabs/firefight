---
name: incident_command
when: Something is broken for users now, judging impact and severity, deciding whether to declare, coordinating responders, paging, or keeping people informed during an incident
tools: [get_incident, search_similar, what_changed, check_status_page, post_incident_update]
---
What good looks like: the right people know quickly, damage is contained first, the investigation is calm and evidence driven, and everyone affected hears what they need, when they need it.

How to approach it:
1. Judge impact and severity fast: who is affected, how many, which business action, since when. When it is hurting users and nobody declared it, offer to declare (the declaring skill).
2. Stabilise first. Look for the quickest safe mitigation (a rollback, a flag off, a traffic shift, scaling, a failover) while the root cause is still open.
3. Coordinate. Know who leads, who is on call and who owns the affected system. Page when it is needed, through the team's paging tool (the paging_on_call skill). The roles and inviting skills say how to assign the lead and bring people in.
4. Keep a clear timeline: what was seen, what was tried, what changed and when (`what_changed`).
5. Communicate in plain words: what is affected, what is being done, when the next update comes. `post_incident_update` posts to the incident (the updating skill). A public update goes out only once a person approves it.
6. Tell a dependency's outage from your own. `check_status_page` reads the provider's status, and errors that name its host point there.

What to check:
- Current impact, and whether it is growing.
- Recent changes across the workspace.
- Who is on call, and whether they acknowledged (`get_incident` lists the pages and escalations).
- Related incidents, past or current (`search_similar`).

Trade-offs:
- Mitigating fast can hide evidence. Capture what you need first when it costs seconds.
- Over-communicating beats silence during an incident, and each update stays short.

Done means: the impact has stopped and is verified, the incident has a clear summary, people know it is over (the ending skill), and the follow-ups are recorded for the postmortem.

When an alert started a run and nobody is awake, the on_call_alert skill says how to work.

Proactive habits:
- Keep runbooks and on-call information current.
- After each incident, check whether paging and escalation worked as intended.
