---
name: trigger_dev_api
when: A question about Trigger.dev that the other Trigger.dev tools do not answer, such as one deployment or batch, a run's result or attempts, schedules, waitpoints, bulk actions or concurrency limits, or anything else Trigger.dev's API reads, and finding out whether the API offers a read at all
tools: [api_read, list_tasks, list_runs]
references: [api/index.md]
---
`api_read` sends a GET to any path of Trigger.dev's management API for this environment and answers what Trigger.dev said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Promoting a version goes through its own tool, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_tasks` for what is deployed, `list_runs` for runs. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read the API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start /api, as the reference writes them. When the reference lists no read for the question, the API does not offer it. Say so, and give the steps in Trigger.dev's dashboard instead.
3. Put every parameter in `query`, never in the path, with the names the reference gives, such as page[size].
4. A list answers one page. To read on, pass page[after] set to the next the answer's pagination gave.
5. Environment variables come back as their names, with values hidden. When the key's preset cannot make a read, say which preset to give the key in Trigger.dev.
