---
name: inviting
when: Bringing people into an incident channel
tools: [invite_responders, escalate_incident]
---
1. Inviting brings people into the channel and asks nothing of them. When the person wants someone to respond, such as paging the on call, use `escalate_incident` instead.
2. `members` takes emails or platform user ids. For the person asking, pass me.
3. Call `invite_responders` once with every person in `members`.
