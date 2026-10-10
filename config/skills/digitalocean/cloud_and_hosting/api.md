---
name: digitalocean_api
when: A question about DigitalOcean that the other DigitalOcean tools do not answer, such as an app's alerts or domains, one deployment's progress, load balancers, volumes, Kubernetes clusters, firewalls, VPCs, a database's configuration, replicas or backups, projects, or anything else DigitalOcean's API reads, and finding out whether the API offers a read at all
tools: [api_read, list_resources, app_logs]
references: [api/index.md]
---
`api_read` sends a GET to any path of DigitalOcean's API and answers what DigitalOcean said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, restart, scale and reboot tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is there. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read DigitalOcean's API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start /v2, as the reference writes them. When the reference lists no read for the question, the API does not offer it. Say so, and give the steps in the control panel instead.
3. Fill the path's ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass per_page, at most 200, and page for the next while the answer's links say there is a next page.
5. Passwords, keys and secret values come back hidden, and a cluster's kubeconfig, the registry's Docker credentials and an app's log addresses are never read. Read an app's logs with `app_logs`. When DigitalOcean answers that the token lacks a scope, say which read scope to add to the token in DigitalOcean, such as kubernetes:read.
