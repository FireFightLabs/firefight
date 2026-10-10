---
name: netlify_api
when: A question about Netlify that the other Netlify tools do not answer, such as a site's forms and submissions, functions, DNS zones and records, SSL certificate, snippets, a deploy's files, or the team's members and audit log, and finding out whether Netlify's API offers a read at all
tools: [api_read, list_sites]
references: [api/index.md]
---
`api_read` sends a GET to any path of Netlify's API and answers what Netlify said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Putting a site back on an earlier deploy goes through the restore in netlify_wrong_version, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_sites` for the sites. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read Netlify's API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths are written after /api/v1, such as /sites/<site id>/forms. When the reference lists no read for the question, Netlify's API does not offer it. Say so, and give the steps in Netlify's dashboard instead.
3. Fill the path's ids from `list_sites` or an earlier answer, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass per_page, at most 100, and page for the next one.
5. Environment variables, build hooks, notification hooks and add-on settings come back as their names, with values and addresses hidden. When the question needs a value, say which variable to check in Netlify.
