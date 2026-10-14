---
name: instatus_customer_updates
when: Telling customers about an incident on an Instatus page, keeping them updated as it moves and closing it once it is fixed
tools: [list_status_pages, list_components, list_incidents, list_templates, get_incident, create_incident, create_incident_from_template, post_incident_update, update_component]
---
1. Call `list_status_pages` for the page, then `list_components` for what customers see on it and how each stands now.
2. Call `list_incidents`, which lists open ones, so you add to an incident already open rather than opening a second one.
3. Writing on a status page tells customers, so it is only for a person to ask for, in the words they agree to. Draft the title and the message in plain words about what customers notice, never internal names, and confirm them first. `list_templates` shows the words the team already agreed, which `create_incident_from_template` opens with.
4. Each call that posts asks `notify`, which has no default, so ask the person whether subscribers are told rather than choosing for them.
5. Open it with `create_incident`, with `components` set to what customers see, such as DEGRADEDPERFORMANCE or MAJOROUTAGE. Add to it with `post_incident_update` at its new `status`: IDENTIFIED once the cause is known, MONITORING once a fix is out, RESOLVED once it is over, with `components` back to OPERATIONAL.
6. `update_component` sets one component's status without an update, for a change customers should see before there is anything to say.
7. Read it back with `get_incident` and give the person its link.
