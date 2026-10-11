---
name: opsgenie_respond
when: Acknowledging, closing, snoozing, assigning or escalating an Opsgenie alert, bringing someone into it, adding a note to it, or resolving or closing an Opsgenie incident
tools: [get_alert, acknowledge_alert, close_alert, snooze_alert, assign_alert, add_responder, escalate_alert, add_alert_note, list_escalations, search_incidents, resolve_incident, close_incident]
---
1. Read the alert with `get_alert` first, so you act on its current status and who already has it. Name it the same way in every call, with `alert` and `identifier_type`.
2. Pick the change. Acknowledging stops it paging further along its escalation while someone works on it. Snoozing stops it paging until a time. Assigning makes one person its owner. Adding a responder pages a team or a person without taking it off whoever has it. Escalating pages the people of another escalation policy, found with `list_escalations`. A note records what is known, such as the incident it belongs to. Closing ends it once the problem is fixed, which is for a person to decide.
3. Tell the person what will change on which alert, then call the tool with a `note` saying why. The person confirms each call.
4. For an Opsgenie incident, find it with `search_incidents`, then `resolve_incident` once the problem is fixed or `close_incident` to end it for good.
5. Opsgenie does the change a moment after it accepts it. When the answer says it is not done yet, read the alert again with `get_alert`.
6. To wake someone for a Firefight incident, page them with Firefight's page_on_call instead of raising an alert here, so the page stays in step with the incident.
