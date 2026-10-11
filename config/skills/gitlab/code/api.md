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

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /projects/{id}: One project, with its default branch, visibility and settings.
- GET /projects/{id}/pipelines (ref, status, source, sha, updated_after, per_page, page): The project's pipelines, newest first, by branch, status or source.
- GET /projects/{id}/pipelines/latest (ref): The latest pipeline on a branch, with its status.
- GET /projects/{id}/pipelines/{pipeline_id}: One pipeline, with its status, commit, who started it and how long it took.
- GET /projects/{id}/pipelines/{pipeline_id}/jobs (page, per_page): A pipeline's jobs, each with its stage, status and runner.
- GET /projects/{id}/pipelines/{pipeline_id}/bridges (page, per_page): A pipeline's jobs that start pipelines downstream, with their status.
- GET /projects/{id}/pipelines/{pipeline_id}/test_report_summary: How many tests passed, failed and were skipped in a pipeline.
- GET /projects/{id}/jobs (scope, per_page, page): The project's jobs, newest first, by status.
- GET /projects/{id}/jobs/{job_id}: One job, with its status, failure reason, runner and timings.
- GET /projects/{id}/pipeline_schedules (page, per_page): Scheduled pipelines, with their branch, timing and whether each is active.
- GET /projects/{id}/deployments (environment, status, updated_after, order_by, sort, per_page, page): Deployments, newest first, by environment or status.
- GET /projects/{id}/deployments/{deployment_id}: One deployment, with its commit, job, status and who ran it.
- GET /projects/{id}/deployments/{deployment_id}/merge_requests (per_page, page): The merge requests a deployment shipped.
- GET /projects/{id}/environments (page, per_page): The project's environments and their state.
- GET /projects/{id}/environments/{environment_id}: One environment, with its last deployment.
- GET /projects/{id}/freeze_periods (page, per_page): Deploy freeze periods and when each starts and ends.
- GET /projects/{id}/resource_groups (page, per_page): Resource groups that make deploy jobs wait their turn.
- GET /projects/{id}/feature_flags (page, per_page): The project's feature flags and whether each is on.
- GET /projects/{id}/releases (page, per_page): Releases, newest first.
- GET /projects/{id}/repository/tags (order_by, sort, per_page, page): The repository's tags.
- GET /projects/{id}/repository/commits (ref_name, path, since, until, per_page, page): Commits on a branch or touching a path, newest first, between two times.
- GET /projects/{id}/repository/commits/{sha}: One commit, with its author, message and pipeline.
- GET /projects/{id}/repository/commits/{sha}/statuses (ref, page, per_page): The status checks reported on a commit.
- GET /projects/{id}/repository/compare (from, to): What changed between two branches, tags or commits.
- GET /projects/{id}/merge_requests (state, target_branch, updated_after, order_by, per_page, page): Merge requests, by state, target branch or when they were merged.
- GET /projects/{id}/merge_requests/{merge_request_iid}: One merge request, with its state, who merged it and its pipeline.
- GET /projects/{id}/protected_branches (page, per_page): Protected branches and who can push and merge to each.
- GET /projects/{id}/audit_events (created_after, created_before, per_page, page): Who changed what in the project and when.
- GET /groups/{id}/audit_events (created_after, created_before, per_page, page): Who changed what in the group and when.
- GET /projects/{id}/events (action, after, before, per_page, page): Recent activity in the project, such as pushes, merges and comments.
- GET /projects/{id}/members/all (state, page, per_page): Who has access to the project, inherited members included, and at which level.
- GET /groups/{id}/members/all (state, page, per_page): Who has access to the group, inherited members included, and at which level.
- GET /projects/{id}/variables (page, per_page): The project's CI/CD variables, by name, never their values.
- GET /projects/{id}/deploy_tokens (page, per_page): The project's deploy tokens, with their scopes and when each expires.
- GET /projects/{id}/deploy_keys (page, per_page): The project's deploy keys and whether each can write.
- GET /personal_access_tokens (state, page, per_page): Personal access tokens, with their scopes, last use and expiry, never their values.
- GET /projects/{id}/runners (type, status, page, per_page): The runners the project can use and whether each is online.
- GET /projects/{id}/hooks (page, per_page): The project's webhooks and the events each one sends.
- GET /projects/{id}/pages/domains (page, per_page): The project's Pages domains and their certificates.
- GET /projects/{id}/statistics: How often the project was fetched over the last 30 days.
