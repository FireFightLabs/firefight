---
name: github_triage
when: Any question about a GitHub repository during an incident, such as what shipped, whether its Actions workflows pass, or what changed before something broke
tools: [resource_status, recent_deploys, search_logs, list_repositories, running_commit, changes_before]
references: [deployments/deployment-environments.md]
---
How GitHub is reached: `resource_status`, `recent_deploys` and `search_logs` ask GitHub about a repository on the resource map by its owner/name. GitHub's own tools take any repository the installation can see, named the same way in `repo`.

1. Find the repository. If it is not on the map, call `list_repositories` and match the service to a repository by name.
2. Call `resource_status` for the repository to see the latest run of each GitHub Actions workflow on its default branch, the jobs and steps that failed, and what each deployment environment last received.
3. Call `recent_deploys` for what went out, newest first. A job that names an environment writes a deployment, so deploys from Actions are there too. A deployment minutes before the problem began is the first suspect.
4. Call `running_commit` with the time the problem started as `at` for the commit that was running then and the one before it, or `changes_before` with that time and what the clues name, to rank every change across the repositories.
5. Then load the skill that fits: github_failing_build when a workflow fails, github_rerun to rerun, start or cancel a workflow once the person wants it, github_deploys for what a deployment changed, github_code to read the code at the running commit.
6. Give the person the GitHub links each answer carries, so they can check what you found.
