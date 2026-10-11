---
name: notion_runbooks
when: Finding the runbook, architecture page or postmortem in Notion for the failing service or the symptom, before or while investigating
tools: [notion_search, notion_fetch]
---
1. Search with `notion_search`, with a `query` naming the service and the word runbook, then the symptom or the error's own words, then the service with architecture or postmortem. Run more than one search, since a page is titled the way its team talks.
2. Read the two or three likeliest pages with `notion_fetch`, its `id` being the page's address or id from the search. Prefer a page edited recently, and say when the one you use was last edited, since a stale runbook can point at what no longer exists.
3. Follow the steps the runbook gives against what the incident shows, and say which ones you checked, which ones held and which ones did not apply.
4. Give the person each page you used with its link, and quote the step you are relying on rather than retelling it. When no page covers the service, say so plainly, and offer to add what was learned to the handbook.
