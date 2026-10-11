---
name: linear_triage
when: Finding Linear issues tied to an incident, such as a known bug in the failing service, an earlier report of the same error, or work in progress that may have caused it
tools: [list_teams, list_issues, get_issue, list_comments, list_projects]
---
1. Find the team that owns the failing service with `list_teams` when the person did not name one, and its projects with `list_projects` when the service has its own.
2. Search with `list_issues`, with words from the error text, the service and the component, asking for 20 issues or fewer. Run more than one search: the error's own words, the service or component name, and the symptom. Keep completed and canceled issues in, since a fix that came back is a regression.
3. Look for work that changed the failing service shortly before the incident began: issues completed in the last day or two in that team or project. A change that shipped just before is the first suspect.
4. Read the likely matches with `get_issue` (`id` is the issue's identifier, such as ENG-42) and their comments with `list_comments`, for what was tried and what was linked.
5. Say which issues match and how closely: the same error in the same service is a likely duplicate, a completed one with the same cause is a possible regression, the same area with a different error is only related. Give the person each issue's identifier, status and link.
