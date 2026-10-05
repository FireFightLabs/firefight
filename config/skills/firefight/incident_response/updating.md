---
name: updating
when: Posting an update on an incident, or changing its status, severity or type while it is live
tools: [get_form, post_incident_update]
---
1. Call `get_form` with `form` set to update. It says what this workspace asks on an update and the choices for status, severity and type.
2. `message` says what was found, what is being done and what happens next, in plain words for the responders in the channel.
3. Write `message` as markdown with real line breaks. Open with one sentence, then a blank line and one bullet per point, each on its own line starting with a dash and a space, when there is more than one. Leave links as plain URLs or as [text](url). Never run points together on one line and never type bullet characters such as •, because the dashboard and the incident channel draw the list from the line breaks.
4. Send only what changes. A required answer left out keeps what the incident already has.
5. Call `post_incident_update` with the `incident` and the `answers`.
