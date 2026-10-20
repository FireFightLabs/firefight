---
name: bitbucket_changes
when: Finding what a Bitbucket deployment or merge changed before something broke and who to ask about it, or deploying an earlier deployment again
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup, list_tags, redeploy, ci_runs]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that brought them with their approvers, the changed files with migrations, config and dependencies first, who owns them from the repository's .bitbucket/CODEOWNERS, and every diff.
3. When no deployment is recorded, call `merged_pull_requests` with `since` set a few hours before the problem. Bitbucket keeps no merge time, so each pull request's last update stands for it. Say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `id`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists every environment's deployments with the pipeline that made each one, filtered by `deployment_environment`. `list_tags` shows the repository's tags and the commit each points at.
6. To follow a deployment, `ci_runs` with the environment's name as `name` reads the deployments as runs when no pipeline has that name, and its `run` follows one by the id it gives.
7. `redeploy` puts an earlier deployment back by starting again the pipeline that made it, on that deployment's commit with the same definition, by the deployment's uuid from `recent_deployments`. It changes what runs, so propose it, say which commit goes back out and what it undoes, and call it only once the person agrees. A deployment step a person starts by hand still waits for them in Bitbucket.
8. Say which change most likely caused the problem and why, who wrote and approved it, and link the pull request or commit.
