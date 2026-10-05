---
name: jira_triage
when: Finding Jira issues tied to an incident, such as a known bug in the failing service, an earlier report of the same error, or work in progress that may have caused it
tools: [getaccessibleatlassianresources, searchjiraissuesusingjql, getjiraissue, listjiraissuecomments, listjiraissueremoteissuelinks]
references: [triage/search-patterns.md, jql/jql-patterns.md]
---
1. Every Jira tool needs the site in `cloudId`. Call `getaccessibleatlassianresources` once and pass the site's address from its url, such as https://acme.atlassian.net, as `cloudId`, rather than its id. With the address, each issue you read comes back with its link.
2. Search with `searchjiraissuesusingjql`, `jql` written from the error text, the service and the component, and `maxResults` of 20 or fewer. Run more than one search: the error's own words with text ~, the service or component name, and the symptom. Keep resolved issues in, since a fix that came back is a regression. Order by updated DESC so recent work comes first.
3. Look for work that changed the failing service shortly before the incident began: issues moved to done or deployed in the last day or two, with updated >= -2d in the query. A change that shipped just before is the first suspect.
4. Read the likely matches with `getjiraissue` (`issueIdOrKey` is the key, such as OPS-42), their comments with `listjiraissuecomments`, and their links with `listjiraissueremoteissuelinks` for the pages and other links tied to them.
5. Say which issues match and how closely: the same error in the same service is a likely duplicate, a resolved one with the same cause is a possible regression, the same area with a different error is only related. Give the person each issue's key, status and link.
