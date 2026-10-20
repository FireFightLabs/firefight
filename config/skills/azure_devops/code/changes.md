---
name: azure_devops_changes
when: Finding what an Azure DevOps deployment or merge changed before something broke and who to ask about it, or deploying an earlier deployment again
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup, release_deployments, redeploy, ci_runs]
references: [pipelines/deployment-jobs.md, pipelines/environments.md, repos/pull-requests.md, repos/branch-policies.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that merged them with their approvers, the changed files with migrations, config and dependencies first, and every diff. Azure Repos names who must review a change in its branch policies rather than a file, so read those through the azure_devops_api skill when the owners matter.
3. When no deployment is recorded, call `merged_pull_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `id`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists what each environment received, each by its deployment id, with the stage and job that deployed it and the run that made it, filtered by `deployment_environment`. A project deploying with classic release pipelines keeps its deployments in `release_deployments`, each by an id such as release/14/3. A run or release waiting for an approval says so, and `ci_runs` follows it.
6. `redeploy` puts an earlier deployment back. For a YAML pipeline it reruns the stage that deployed it, in the run that made it, on that run's commit, by the deployment id from `recent_deployments`, which is how Azure DevOps rolls back a YAML pipeline. For a classic release it deploys that release to its stage again, by the id from `release_deployments`. Only a deployment that succeeded goes back out. It changes what runs, so propose it, say which commit or release goes back out and what it undoes, and call it only once the person agrees. An approval or check on the stage or its environment still waits for a person.
7. Say which change most likely caused the problem and why, who wrote and approved it, and link the pull request or commit.
