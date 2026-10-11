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

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /sites (filter, page, per_page): The sites the connection can see, with each one's URL, repository and published deploy.
- GET /sites/{site_id}: One site, with its domains, build settings, repository and published deploy.
- GET /{account_slug}/sites (page, per_page): The sites in one team.
- GET /sites/{site_id}/deploys (state, branch, page, per_page): A site's deploys, newest first, with each one's state, branch, commit and context.
- GET /sites/{site_id}/deploys/{deploy_id}: One deploy of a site, with its state, error, commit, branch and timings.
- GET /deploys/{deploy_id}: One deploy by its id alone, with its state, error and commit.
- GET /sites/{site_id}/builds (page, per_page): A site's builds, newest first, with each one's state and error.
- GET /builds/{build_id}: One build, with its state, error, deploy and timings.
- GET /{account_id}/builds/status: The team's build capacity, with how many builds are running and queued.
- GET /sites/{site_id}/deployed-branches: The branches a site deploys, each with its latest deploy.
- GET /sites/{site_id}/plugin_runs/latest (packages, state): The latest runs of a site's build plugins, with each one's outcome.
- GET /sites/{site_id}/functions (filter): A site's functions, with their runtime and schedule.
- GET /sites/{site_id}/traffic_splits: A site's split tests, with the branches and how traffic is shared.
- GET /sites/{site_id}/dns: The DNS zones that serve a site's domains.
- GET /dns_zones: The DNS zones Netlify hosts, with their names and nameservers.
- GET /dns_zones/{zone_id}: One DNS zone, with its domain, nameservers and DNSSEC state.
- GET /dns_zones/{zone_id}/dns_records: The records in a DNS zone, with each one's type, host and value.
- GET /sites/{site_id}/ssl: A site's TLS certificate, with its state, domains and expiry.
- GET /sites/{site_id}/ssl/certificates (domain): Every certificate a site holds, with their domains and expiry.
- GET /accounts: The teams the connection belongs to, with their plan and capabilities.
- GET /accounts/{account_id}: One team, with its plan, usage and capabilities.
- GET /accounts/{account_id}/audit (page, per_page): The team's audit log, such as who changed settings, members or deploys, newest first.
- GET /{account_slug}/members: The team's members and their roles.
- GET /{account_slug}/members/{member_id}: One team member, with their role and the sites they can reach.
- GET /accounts/{account_id}/env: The team's environment variables, by name and scope, never their values.
- GET /api/v1/sites/{site_id}/env: A site's environment variables, by name and scope, never their values.
- GET /sites/{site_id}/build_hooks: A site's build hooks, by title and branch, with only the host they call.
- GET /hooks (site_id): A site's notification hooks, such as deploy alerts, by event and type.
- GET /sites/{site_id}/database: A site's database and its status.
- GET /sites/{site_id}/database/branches: A site database's branches.
- GET /sites/{site_id}/database/migrations (branch): A site database's migrations, with which have run.
- GET /sites/{site_id}/database/snapshots: A site database's snapshots, with when each was taken.
- GET /deploy_keys: The deploy keys Netlify uses to clone repositories, by id and public key only.
- GET /user: The user the connection acts as.
