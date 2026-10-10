---
name: gitlab_api
when: A question about GitLab that the other GitLab tools do not answer, such as a project's environments and their protections, protected branches, releases, members, container registry or a group's settings, or anything else GitLab's REST API reads, and finding out whether GitLab's API offers a read at all
tools: [api_read, list_projects]
references: [api/index.md]
---
`api_read` sends a GET to any path of GitLab's REST API on this connection's instance and answers what GitLab said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through GitLab's other tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_projects` for what the token can see, and the merge request, pipeline and file tools for those. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read GitLab's REST API offers by area, then the area's page it names for the parameters and the fields each read answers. When the reference lists no read for the question, GitLab's API does not offer it. Say so, and give the steps in GitLab instead.
3. A read inside a project names it by its path with its groups in `project`, such as acme/platform/checkout, and `path` is then what comes after /projects/:id, such as /environments. A read outside one, such as a group's, goes in `path` alone. Put every parameter in `query`, never in the path.
4. A list answers one page. Pass per_page, at most 100, and read on with page 2, 3 and so on while a page comes back full.
5. CI/CD variables, pipeline triggers, integrations and webhooks come back as their names, with values hidden. A Terraform state is never read, since it holds every value it manages. Raw files, archives, job logs and artifacts are not read here. Use the file tools and the job log tool in the failing pipeline skill.
