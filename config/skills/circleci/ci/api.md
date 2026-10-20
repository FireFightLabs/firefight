---
name: circleci_api
when: A question about CircleCI that the other CircleCI tools do not answer, such as a project's schedules, contexts, insights and flaky tests, an organization's settings, and finding out whether CircleCI's API offers a read at all
tools: [api_read, list_projects, ci_status, ci_runs, get_job_logs]
references: [api/index.md]
---
`api_read` sends a GET to any path of CircleCI's API and answers what CircleCI said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Rerunning, cancelling, approving, running a pipeline and rolling back go through their own tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_projects` for the projects and their ids, `ci_status`, `ci_runs` and `get_job_logs` for how CI stands. Reach for `api_read` for the rest.
2. Every path starts with the version of the API it reads. API v2 is in api/index.md (use_skill with this skill and that reference), which lists every read v2 offers by area, each path written after /v2, such as /v2/insights/gh/acme/web/workflows. API v3 has no reference here, so read circleci.com/docs/api/v3/index.md with the web reading tool and write its paths after /v3, such as /v3/projects with filter[org_id] in query. When neither lists a read for the question, CircleCI's API does not offer it. Say so, and give the steps in CircleCI's app instead.
3. A v2 project slug is the one `list_projects` shows, such as gh/acme/web or circleci/<organization id>/<project id>, and v3 takes ids only. Put every parameter in `query`, never in the path.
4. v2 lists answer one page with next_page_token, passed back as page-token. v3 lists answer page.next, passed back as page[cursor], with page[limit] no higher than the operation allows.
5. Environment variables, checkout keys, exporters and webhooks come back as their names, with values and addresses hidden. A step's output is read with `get_job_logs`, and a usage export or a runner's token is never read.

Key reads, the ones an investigation reaches for most, with what to fill in braces.
- GET /v2/insights/{project-slug}/workflows: How often each of a project's workflows succeeds and how long it takes.
- GET /v2/insights/{project-slug}/flaky-tests: A project's tests that failed and then passed on the same commit.
- GET /v2/insights/{project-slug}/workflows/{workflow-name}: Recent runs of one workflow with their duration and status.
- GET /v2/project/{project-slug}/schedule: A project's scheduled pipelines.
- GET /v2/project/{project-slug}/envvar: A project's environment variables, by name.
- GET /v2/context (owner-id): An organization's contexts.
- GET /v2/context/{context_id}/restrictions: Which projects and groups may use a context.
- GET /v2/pipeline/{pipeline-id}/config: The config a run compiled, which says why its workflows did or did not start.
- GET /v2/pipeline/{pipeline_id}/values: The pipeline values a run had, such as its branch and parameters.
- GET /v2/deploy/environments (org-id, page-size): An organization's deploy environments.
- GET /v3/projects (filter[org_id]): An organization's projects by id and name.
- GET /v3/runs/{id}: One run with how it stands and the commit it built.
