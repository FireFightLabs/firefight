---
name: github_deploys
when: Finding what a GitHub deployment or merge changed before something broke, and who to ask about it
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup]
references: [deployments/deployments-and-environments.md, deployments/view-deployment-history.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that brought them with their reviewers, the changed files with migrations, config and dependencies first, who owns them from CODEOWNERS, and every diff.
3. When no deployment is recorded, the pipeline does not write GitHub deployments. Call `merged_pull_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `number`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists deployments newest first with their outcome, filtered by `deployment_environment`, and `limit` reads more than the latest three. An environment with required reviewers or a wait timer holds a deployment until it is approved, so a deployment waiting is not a failed one.
6. Say which change most likely caused the problem and why, who wrote and reviewed it, and link the pull request or commit.
