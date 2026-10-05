---
name: opsgenie_respond
when: Acknowledging an Opsgenie alert, escalating it to an escalation policy, or adding a note to it
tools: [get_alert, acknowledge_alert, escalate_alert, add_alert_note, list_escalations]
---
1. Read the alert with `get_alert` first, so you act on its current status and who already has it. Name it the same way in every call, with `alert` and `identifier_type`.
2. Pick the change. Acknowledging stops it paging further along its escalation while someone works on it. Escalating pages the people of another escalation policy, found with `list_escalations` and named in `escalation`. A note records what is known, such as the incident it belongs to.
3. Tell the person what will change on which alert, then call `acknowledge_alert`, `escalate_alert` or `add_alert_note`, with a `note` saying why. The person confirms each call.
4. Opsgenie does the change a moment after it accepts it. When the answer says it is not done yet, read the alert again with `get_alert`.
