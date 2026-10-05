---
name: gitlab_changes
when: Finding what a GitLab deployment or merge changed before something broke, who to ask about it, and how a deployment is rolled back
tools: [recent_deployments, running_commit, compare_commits, merged_merge_requests, mr_lookup, commit_lookup]
references: [environments/deployments.md, environments/deployment-safety.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the merge requests that brought them with their approvers, the changed files with migrations, config and dependencies first, who owns them from the project's CODEOWNERS, and every diff.
3. When no deployment is recorded, call `merged_merge_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `mr_lookup` by its `iid`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists an environment's deployments with the job that ran each one, filtered by `deployment_environment`. Two deployments to one environment that ran at the same time can leave either one live, so check their order.
6. When a rollback is the fix, say how GitLab does it: on the environment's page, Rollback environment next to an earlier successful deployment runs that deployment's job again, which makes a new deployment of the older commit. Only the deployment job runs, so a job that needs artifacts an earlier job made has to be run by hand. A person does this, never Halon while investigating.
7. Say which change most likely caused the problem and why, who wrote and approved it, and link the merge request or commit.
