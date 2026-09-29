---
name: ending
when: Closing, resolving or cancelling one or more incidents
tools: [search_incidents, get_form, resolve_incident, cancel_incident]
---
1. Resolve when the problem was real and is over. Cancel when it turned out not to be an incident, such as a false alarm, a duplicate or a mistake. When it is not clear which, ask.
2. When the person named incidents by what they are rather than by identifier, such as "both open ones", find them with `search_incidents` first.
3. Call `get_form` once with `form` set to resolve or cancel. A required answer left out keeps what the incident already has, so send only what the person said should change. Leave out a field marked asked false.
4. Call `resolve_incident` or `cancel_incident` once per incident, with its `incident` and any `answers`. Say which ones ended.
