---
name: gitlab_triage
when: Any question about a GitLab project during an incident, such as what shipped, whether its pipelines pass, or what changed before something broke
tools: [resource_status, recent_deploys, search_logs, list_projects, running_commit, pipelines]
references: [environments/environments.md]
---
How GitLab is reached: `resource_status`, `recent_deploys` and `search_logs` ask GitLab about a project on the resource map by its path with its groups, such as acme/platform/checkout. GitLab's own tools take any project the token can read, named the same way in `repo`.

1. Find the project. If it is not on the map, call `list_projects` and match the service to a project by name.
2. Call `resource_status` for the project to see whether the latest pipeline on its default branch failed, which jobs failed, since when it fails, and what each environment last deployed.
3. Call `recent_deploys` for what went out, newest first, with the environment, the commit, who ran it and its job. A deployment minutes before the problem began is the first suspect.
4. Call `running_commit` with the time the problem started as `at` for the commit that was running then and the one before it. It falls back to the default branch when no deployment is recorded, and says so.
5. Call `pipelines` with `status` failed for the failures around the time asked, when the default branch is not the one that broke.
6. Then load the skill that fits: gitlab_failing_pipeline when a pipeline or job fails, gitlab_rerun to retry, run or cancel a pipeline once the person wants it, gitlab_changes for what a deployment changed, gitlab_code to read the code at the running commit.
7. Give the person the GitLab links each answer carries, so they can check what you found.
