---
name: paging_on_call
when: The person asks to page or wake whoever is on call, or a change waits for an approval nobody working the incident can give
tools: [get_incident, page_on_call, escalate_incident]
---
1. Find who is on call for what broke with the connected on-call tool's skill, loaded with use_skill. Name the person the schedule has on call now, and the service or team whose escalation has them on call. With no on-call tool connected, ask the person who to page.
2. Call `get_incident` and check that they are not already paged: its pages list what was raised in an on-call tool and where each stands, and the timeline names everyone the incident was escalated to.
3. With an on-call tool connected, call `page_on_call` with `target` set to that service or team, as the tool's description says for each connection, `person` set to their email and `reason` set to what they need before they open the channel: what is broken and since when, the evidence with its links, and the fix you propose or are waiting on. The tool's own escalation wakes them, and acknowledging or resolving the page there or the incident here reaches the other side.
4. With none, or when page_on_call says the tool cannot page, call `escalate_incident` with `member` set to their email and the same `reason`. Escalating is how a person is paged here.
5. Either way they are whoever is on call for the incident. An approval rule that lets whoever is on call approve then asks them directly when nobody working the incident can approve, so say that a change waiting on approval can now be decided by them.
6. Say who you paged and where. A page in the on-call tool reminds them by its own escalation, and an escalation here reminds them when nobody acknowledges. A page waiting for approval is raised once an admin approves it.
