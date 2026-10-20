---
name: azure_devops_triage
when: Any question about an Azure DevOps repository or pipeline during an incident, such as what shipped, whether its pipeline runs pass, or what changed before something broke
tools: [resource_status, recent_deploys, search_logs, run_history, list_repositories, running_commit, pipelines, release_deployments]
references: [pipelines/environments.md, pipelines/runs.md]
---
How Azure DevOps is reached: `resource_status`, `recent_deploys`, `search_logs` and `run_history` ask Azure DevOps about a repository or a pipeline on the resource map. A repository is named project/repository and a pipeline project/pipeline, such as Shop/checkout. Azure DevOps' own tools take any repository or pipeline the token can read, named the same way in `repo` or `pipeline`.

1. Find the repository or pipeline. If it is not on the map, call `list_repositories` and match the service to a repository by name.
2. Call `resource_status` for it to see whether the latest run on the default branch failed, which jobs failed, since when it fails, which approvals are waiting, and what each environment of the project last received.
3. Call `recent_deploys` for what went out, newest first, with the environment, the commit, the stage and job that deployed it and the run that made it. A deployment minutes before the problem began is the first suspect. A project that deploys with classic release pipelines keeps those apart, so call `release_deployments` with the project for them.
4. Call `running_commit` with the time the problem started as `at` for the commit that was running then and the one before it. It falls back to the default branch when no deployment is recorded, and says so.
5. Call `pipelines` with `result` failed for the failed runs around the time asked, when the default branch is not the one that broke.
6. Then load the skill that fits: azure_devops_failing_pipeline when a run or job fails, azure_devops_rerun to run, rerun or cancel a pipeline or answer an approval once the person wants it, azure_devops_changes for what a deployment changed, azure_devops_code to read the code at the running commit.
7. Give the person the Azure DevOps links each answer carries, so they can check what you found.
