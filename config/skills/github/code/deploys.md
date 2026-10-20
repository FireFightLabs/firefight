---
name: github_deploys
when: Finding what a GitHub deployment or merge changed before something broke and who to ask about it, why a deploy waits, or deploying an earlier deployment again
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup, list_environments, redeploy, ci_runs]
references: [deployments/deployments-and-environments.md, deployments/view-deployment-history.md]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that brought them with their reviewers, the changed files with migrations, config and dependencies first, who owns them from CODEOWNERS, and every diff.
3. When no deployment is recorded, the pipeline does not write GitHub deployments. Call `merged_pull_requests` with `since` set a few hours before the problem, and say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `number`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists deployments newest first with their id, outcome, log and the address each serves at, filtered by `deployment_environment`, and `limit` reads more than the latest three. An environment with required reviewers or a wait timer holds a deployment until it is approved, so a deployment waiting is not a failed one. `list_environments` says which rules hold a deploy to each environment and who must approve it.
6. Say which change most likely caused the problem and why, who wrote and reviewed it, and link the pull request or commit.
7. To follow a deployment, `ci_runs` with the environment's name as `name`, such as production, reads the deployments as runs when no workflow has that name, and its `run` follows one by the id it gives.
8. `redeploy` puts an earlier deployment back by running again the GitHub Actions job that made it, on that deployment's commit. It changes what runs, so propose it with the deployment's id from `recent_deployments` as `deployment`, say which commit goes back out and what it undoes, and call it only once the person agrees. A deployment another system made names no Actions run, so say that system deploys it again.
