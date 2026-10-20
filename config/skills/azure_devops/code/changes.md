---
name: azure_devops_changes
when: Finding what an Azure DevOps deployment or merge changed before something broke, who to ask about it, and how a deployment is rolled back
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup, release_deployments]
references: [pipelines/deployment-jobs.md, pipelines/environments.md, repos/pull-requests.md, repos/branch-policies.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that merged them with their approvers, the changed files with migrations, config and dependencies first, and every diff. Azure Repos names who must review a change in its branch policies rather than a file, so read those through the azure_devops_api skill when the owners matter.
3. When no deployment is recorded, call `merged_pull_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `id`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists what each environment received, with the stage and job that deployed it and the run that made it, filtered by `deployment_environment`. A project deploying with classic release pipelines keeps its deployments in `release_deployments`.
6. When a rollback is the fix, say how Azure DevOps does it: run the pipeline again on the earlier commit or tag, which the azure_devops_rerun skill does, or in a classic release pipeline redeploy the earlier release to that stage. A deployment job's own rollback steps run only when the pipeline defines them. A person decides this, never Halon while investigating.
7. Say which change most likely caused the problem and why, who wrote and approved it, and link the pull request or commit.
