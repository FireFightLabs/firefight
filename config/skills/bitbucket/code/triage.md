---
name: bitbucket_triage
when: Any question about a repository in Bitbucket during an incident, such as what shipped, whether its pipelines pass, or what changed before something broke
tools: [resource_status, recent_deploys, search_logs, list_repositories, running_commit, pipelines]
---
How Bitbucket is reached: `resource_status`, `recent_deploys` and `search_logs` ask Bitbucket about a repository on the resource map by its path, workspace/repository. Bitbucket's own tools take any repository the token can read, named the same way in `repo`.

1. Find the repository. If it is not on the map, call `list_repositories` and match the service to a repository by name.
2. Call `resource_status` for the repository to see whether its latest pipeline on the main branch failed, since when it fails, and what each environment last deployed.
3. Call `recent_deploys` for what went out, newest first, with the environment, the commit and the pipeline that made each deployment. A deployment minutes before the problem began is the first suspect.
4. Call `running_commit` with the time the problem started as `at` for the commit that was running then and the one before it. It falls back to the main branch when no deployment is recorded, and says so.
5. Then load the skill that fits: bitbucket_failing_pipeline when a pipeline fails, bitbucket_rerun to run, run again or stop a pipeline once the person wants it, bitbucket_changes for what a deployment changed, bitbucket_code to read the code at the running commit.
6. Give the person the Bitbucket links each answer carries, so they can check what you found.
