---
name: sentry_triage
when: Any question about errors Sentry collects from a service, such as what is failing, since when, or whether a release caused it
tools: [search_issues, recent_deploys, get_sentry_resource, execute_sentry_tool, search_sentry_tools, find_organizations, find_projects]
---
How Sentry is reached: search_errors and `recent_deploys` ask Sentry for a resource on the map by the Sentry project of the same name, when the connection is held to one organization. Sentry's own tools reach every project in the organization, including ones that are not on the map. When one asks for organizationSlug, `find_organizations` gives it, and `find_projects` gives a project's slug when its name differs from the service's. Many of Sentry's tools are not listed on their own: `search_sentry_tools` finds one by what it does, and `execute_sentry_tool` runs it with its name and its arguments. Sentry's answers carry the page of each issue, release and trace they name, so give those links to the person.

1. Call `search_issues` for the project in projectSlugOrId, with the query is:unresolved lastSeen:-1h and sort freq, for what is failing most right now. Each issue is one kind of error, with its events, the users it reached, and when it was first and last seen.
2. Look at when each began. An issue first seen when the trouble began is new, and the first suspect. The query is:regressed finds issues that came back after they were resolved, and is:escalating finds ones happening far more than usual. Both are worth a look. An issue seen steadily for weeks is background.
3. Call `recent_deploys` for the service. A release whose deploy finished shortly before the first new issue is the next suspect, so load the sentry_bad_release skill.
4. Call `get_sentry_resource` with resourceType issue and the issue's short id, such as WEB-1Z43, in resourceId. It gives the stack trace with the most relevant frame of the app's own code, the tags and the latest event. Then load the sentry_errors skill to follow it to its cause.
