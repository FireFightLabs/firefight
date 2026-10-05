---
name: jira_follow_ups
when: Opening a Jira issue for work an incident needs, during it or after it, adding what the incident found to an existing issue, or linking issues to each other
tools: [getaccessibleatlassianresources, listjiraprojects, listjiraprojectissuetypesmetadata, getjiraissuetypemetawithfields, searchjiraissuesusingjql, createjiraissue, addoreditjiraissuecomment, listjiraissuelinktypes, createjiraissuelink, lookupjiraaccountid]
references: [triage/bug-report-templates.md]
---
1. Pass the site's address as `cloudId`, from the url `getaccessibleatlassianresources` gives, such as https://acme.atlassian.net, so the issue you create comes back with its link.
2. Before creating anything, search with `searchjiraissuesusingjql` for an open issue that already covers the work. If one does, add what the incident found to it with `addoreditjiraissuecomment` (`issueIdOrKey`, `commentBody`) instead of opening a second.
3. Find the project with `listjiraprojects` when the person did not name one, and its issue types with `listjiraprojectissuetypesmetadata` (`projectIdOrKey`). Use Bug for something broken and Task otherwise, when the project has them.
4. Write the issue: `summary` names the component and what to do, and `description` says what happened in the incident, its identifier (such as INC-42) and title, the evidence, and what done looks like. To assign it, find the person with `lookupjiraaccountid`.
5. Tell the person the project, type, summary and assignee before calling `createjiraissue` (`projectKey`, `issueType`, `summary`, `description`). If Jira refuses it for a missing field, read the fields with `getjiraissuetypemetawithfields` and ask the person for the values.
6. To tie issues together, such as a follow-up and the bug it fixes, read the names Jira allows with `listjiraissuelinktypes` and link them with `createjiraissuelink`.
7. Give the person the new issue's key and link. In a chat about an incident, Firefight keeps the new issue on it with its link by itself and says so in the answer, so do not add it again. Say how with `keep_on_incident_as` on `createjiraissue`: `action` for work to do while the incident is live, such as a fix or a mitigation, and `followup` for work after it, such as hardening or a cleanup. Left out, it is an action while the incident is live and a follow-up once it is over. Otherwise, when the issue is for an incident, record it there with `create_action_item`, naming the key and link, so the incident and the issue point at each other.
8. When the issue is moved to a done status, Firefight marks its item done on the incident by itself once it can read the issue's status, and says so in the answer.
