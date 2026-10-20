---
name: gitlab_changes
when: Finding what a GitLab deployment or merge changed before something broke, who to ask about it, why a deploy waits, approving one, and rolling a deployment back
tools: [recent_deployments, running_commit, compare_commits, merged_merge_requests, mr_lookup, commit_lookup, list_environments, redeploy, approve_deployment, stop_environment, list_releases, release_lookup, list_tags, ci_runs]
references: [environments/deployments.md, environments/deployment-safety.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the merge requests that brought them with their approvers, the changed files with migrations, config and dependencies first, who owns them from the project's CODEOWNERS, and every diff.
3. When no deployment is recorded, call `merged_merge_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `mr_lookup` by its `iid`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists an environment's deployments with the job that ran each one, filtered by `deployment_environment`. Two deployments to one environment that ran at the same time can leave either one live, so check their order.
6. When a rollback is the fix, `redeploy` does what GitLab's own rollback does: it runs again the job that made an earlier successful deployment, by the deployment's id from `recent_deployments` as `deployment`, which makes a new deployment of the older commit. Only the deployment job runs, so a job that needs artifacts an earlier job made may fail. It changes what runs, so propose it, say which commit goes back out and what it undoes, and call it only once the person agrees, never while investigating.
7. A deployment to a protected environment that needs approval is blocked, and waiting in `ci_runs`. `list_environments` says who may deploy to each environment and how many approvals a deploy needs. `approve_deployment` approves or rejects it by its `deployment` id with a `comment`, only when the person asks or a runbook step says to. It needs GitLab Premium or Ultimate and a token whose user may approve for that environment.
8. `stop_environment` stops an environment by its id from `list_environments`, such as a review app nobody needs, which runs its stop job. `force` stops it without that job. Say what stops serving before the person agrees.
9. `list_releases`, `release_lookup` and `list_tags` show what was released and tagged, such as the release a tag deployed.
10. To follow a deployment, `ci_runs` with the environment's name as `name` reads the deployments as runs when no pipeline has that name, and its `run` follows one by the id it gives.
11. Say which change most likely caused the problem and why, who wrote and approved it, and link the merge request or commit.
