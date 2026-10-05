---
name: bitbucket_changes
when: Finding what a Bitbucket deployment or merge changed before something broke, and who to ask about it
tools: [recent_deployments, running_commit, compare_commits, merged_pull_requests, pr_lookup, commit_lookup]
---
1. Call `running_commit` with `repo` and the time the problem started as `at`, and `deployment_environment` when it is not production. It names the commit that was running and the one deployed before it.
2. Call `compare_commits` with those two as `base` and `head`. It lists the commits and the pull requests that brought them with their approvers, the changed files with migrations, config and dependencies first, who owns them from the repository's .bitbucket/CODEOWNERS, and every diff.
3. When no deployment is recorded, call `merged_pull_requests` with `since` set a few hours before the problem. Bitbucket keeps no merge time, so each pull request's last update stands for it. Say a merge is not proof of a deploy.
4. Read a suspect with `pr_lookup` by its `id`, or `commit_lookup` by its `sha`.
5. `recent_deployments` lists every environment's deployments with the pipeline that made each one, filtered by `deployment_environment`.
6. Say which change most likely caused the problem and why, who wrote and approved it, and link the pull request or commit.
