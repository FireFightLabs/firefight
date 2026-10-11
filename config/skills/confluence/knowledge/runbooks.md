---
name: confluence_runbooks
when: Finding the runbook, architecture page or postmortem in Confluence for the failing service or the symptom, before or while investigating
tools: [getaccessibleatlassianresources, searchconfluence, getconfluencecontent]
---
1. Every Confluence tool needs the site in `cloudId`. Call `getaccessibleatlassianresources` once and pass the site's address from its url, such as https://acme.atlassian.net, as `cloudId`, rather than its id. With the address, each page you read comes back with its link.
2. Search with `searchconfluence`, `cql` written from the service and the symptom, such as type = page AND text ~ "checkout runbook" ORDER BY lastmodified DESC. Run more than one search: the service with runbook, the symptom or the error's own words, and the service with architecture or postmortem.
3. Read the two or three likeliest pages with `getconfluencecontent`, `content_id` being the page's id from the search and `content_format` markdown. Prefer a page edited recently, and say when the one you use was last edited, since a stale runbook can point at what no longer exists.
4. Follow the steps the runbook gives against what the incident shows, and say which ones you checked, which ones held and which ones did not apply.
5. Give the person each page you used with its link, and quote the step you are relying on rather than retelling it. When no page covers the service, say so plainly, and offer to add what was learned to the handbook.
