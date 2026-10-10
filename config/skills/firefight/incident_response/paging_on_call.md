---
name: paging_on_call
when: The person asks to page or wake whoever is on call, or a change waits for an approval nobody working the incident can give
tools: [get_incident, escalate_incident]
---
1. Find who is on call for what broke with the connected on-call tool's skill, loaded with use_skill. Name the person the schedule has on call now. With no on-call tool connected, ask the person who to page.
2. Call `get_incident` and check that they are not already paged: the timeline names everyone the incident was escalated to.
3. Call `escalate_incident` with `member` set to their email and `reason` set to what they need before they open the channel: what is broken and since when, the evidence with its links, and the fix you propose or are waiting on.
4. Escalating is how a person is paged here, and it makes them whoever is on call for the incident. An approval rule that lets whoever is on call approve then asks them directly when nobody working the incident can approve, so say that a change waiting on approval can now be decided by them.
5. Say who you paged and that they get a reminder when nobody acknowledges.
