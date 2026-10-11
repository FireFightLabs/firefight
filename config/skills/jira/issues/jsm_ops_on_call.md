---
name: jsm_ops_on_call
when: Finding who is on call in Jira Service Management Operations, where Opsgenie's teams move, or who an alert there reaches next
tools: [getaccessibleatlassianresources, getjsmopsscheduleinfo, getjsmopsteaminfo]
---
1. Every Atlassian tool needs the site in `cloudId`. Call `getaccessibleatlassianresources` once and pass the site's address from its url, such as https://acme.atlassian.net.
2. Call `getjsmopsscheduleinfo` for the on-call schedules and who each has on call now and next. Atlassian offers the Operations tools only to a connection made with an API token, once an organization admin allowed API tokens for its server, so a refusal saying that means this connection cannot read Operations. Tell the person, and that reconnecting Jira with an API token lets it.
3. Call `getjsmopsteaminfo` for the team that owns a schedule and its members, when the person asks who else could help.
4. Name who is on call now first, then who comes next and when.
