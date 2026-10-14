---
name: statuspage_customer_updates
when: Telling customers about an incident on an Atlassian Statuspage page, keeping them updated as it moves and closing it once it is fixed
tools: [list_pages, list_components, list_incidents, get_incident, count_subscribers, create_incident, post_incident_update, update_component]
---
1. Call `list_pages` for the page, then `list_components` for what customers see on it and how each stands now.
2. Call `list_incidents` with `list` unresolved, so you add to an incident already open rather than opening a second one.
3. Writing on a status page tells customers, so it is only for a person to ask for, in the words they agree to. Draft the title and the message in plain words about what customers notice, never internal names, and confirm them first.
4. `count_subscribers` says how many people an update reaches. Each call that posts asks `deliver_notifications`, which has no default, so ask the person whether subscribers are told rather than choosing for them.
5. Open it with `create_incident`, with `components` set to what customers see, such as degraded_performance or major_outage. Add to it with `post_incident_update` at its new `status`: identified once the cause is known, monitoring once a fix is out, resolved once it is over, with `components` back to operational.
6. `update_component` sets one component's status without an update, for a change customers should see before there is anything to say.
7. Read it back with `get_incident` and give the person its link.
