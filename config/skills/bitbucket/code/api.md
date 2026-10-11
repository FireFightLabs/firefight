---
name: bitbucket_api
when: A question about Bitbucket that the other Bitbucket tools do not answer, such as a repository's deployment environments, branch restrictions, branching model, members and permissions, or a workspace's projects, or anything else Bitbucket's REST API reads, and finding out whether Bitbucket's API offers a read at all
tools: [api_read, list_repositories]
---
`api_read` sends a GET to any path of Bitbucket Cloud's REST API and answers what Bitbucket said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through Bitbucket's other tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_repositories` for what this connection reads, and the pull request, pipeline and file tools for those. Reach for `api_read` for the rest.
2. Find the path in Bitbucket's REST reference before the first call, not by guessing. Bitbucket publishes it at https://developer.atlassian.com/cloud/bitbucket/rest/intro/ with every read listed by area. Read it with the web reading tool, where the workspace allows reading the web. Bitbucket's reference is not copied into Firefight's documentation. When the reference lists no read for the question, Bitbucket's API does not offer it. Say so, and give the steps in Bitbucket instead.
3. Write the path after /2.0, naming the workspace and repository as `list_repositories` shows them, such as /repositories/acme/checkout/environments. A read names a workspace this connection reads, unless it reads every workspace its token can. Put every parameter in `query`, never in the path.
4. A list answers one page. Pass pagelen, at most 100, and read on with page 2, 3 and so on while the answer names a next page.
5. Pipeline and deployment variables and webhooks come back as their names, with values hidden. Downloads, a file's source, diffs and step logs are not read here. Use the file tools, the compare tool and the job log tool in the failing pipeline skill.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /repositories/{workspace}/{repo_slug}: One repository, with its main branch, size and when it was last updated.
- GET /repositories/{workspace}/{repo_slug}/pipelines (target.branch, status, trigger_type, sort, pagelen, page): The repository's pipelines, by branch, status or what started them.
- GET /repositories/{workspace}/{repo_slug}/pipelines/{pipeline_uuid}: One pipeline, with its state, result, commit, who started it and how long it took.
- GET /repositories/{workspace}/{repo_slug}/pipelines/{pipeline_uuid}/steps (pagelen, page): A pipeline's steps, each with its state, result and timings.
- GET /repositories/{workspace}/{repo_slug}/pipelines/{pipeline_uuid}/steps/{step_uuid}: One step of a pipeline, with its image, commands and result.
- GET /repositories/{workspace}/{repo_slug}/pipelines/{pipeline_uuid}/steps/{step_uuid}/test_reports: How many tests passed, failed and were skipped in a step.
- GET /repositories/{workspace}/{repo_slug}/pipelines_config/schedules (pagelen, page): Scheduled pipelines, with their branch, timing and whether each is on.
- GET /repositories/{workspace}/{repo_slug}/pipelines_config/schedules/{schedule_uuid}/executions (pagelen, page): The pipelines a schedule started.
- GET /repositories/{workspace}/{repo_slug}/deployments (pagelen, page): Deployments to each environment, with their state and the commit they shipped.
- GET /repositories/{workspace}/{repo_slug}/deployments/{deployment_uuid}: One deployment, with its environment, state, commit and pipeline.
- GET /repositories/{workspace}/{repo_slug}/environments (pagelen, page): The repository's deployment environments, such as Test, Staging and Production.
- GET /repositories/{workspace}/{repo_slug}/environments/{environment_uuid}: One environment, with its type, lock and restrictions.
- GET /repositories/{workspace}/{repo_slug}/deployments_config/environments/{environment_uuid}/variables (pagelen, page): An environment's deployment variables, by name, never their values.
- GET /repositories/{workspace}/{repo_slug}/pipelines_config/variables (pagelen, page): The repository's pipeline variables, by name, never their values.
- GET /workspaces/{workspace}/pipelines-config/variables (pagelen, page): The workspace's pipeline variables, by name, never their values.
- GET /repositories/{workspace}/{repo_slug}/commits (include, exclude, path, pagelen, page): Commits on a branch or touching a path, newest first.
- GET /repositories/{workspace}/{repo_slug}/commit/{commit}: One commit, with its author, message, date and parents.
- GET /repositories/{workspace}/{repo_slug}/commit/{commit}/statuses (refname, q, sort, pagelen, page): Builds and checks reported on a commit, with their state.
- GET /repositories/{workspace}/{repo_slug}/commit/{commit}/pullrequests (pagelen, page): The pull requests that contain a commit.
- GET /repositories/{workspace}/{repo_slug}/refs/branches (q, sort, pagelen, page): The repository's open branches, with their latest commit.
- GET /repositories/{workspace}/{repo_slug}/refs/tags (q, sort, pagelen, page): The repository's tags, with the commit each points at.
- GET /repositories/{workspace}/{repo_slug}/pullrequests (state, q, sort, pagelen, page): Pull requests, by state, newest first.
- GET /repositories/{workspace}/{repo_slug}/pullrequests/{pull_request_id}: One pull request, with its state, branches, merge commit and who merged it.
- GET /repositories/{workspace}/{repo_slug}/pullrequests/activity (pagelen, page): Recent pull request activity in the repository, such as approvals, updates and comments.
- GET /repositories/{workspace}/{repo_slug}/branch-restrictions (kind, pattern, pagelen, page): Branch restrictions, such as who can push or merge and how many approvals are needed.
- GET /repositories/{workspace}/{repo_slug}/permissions-config/users (pagelen, page): People given access to the repository directly, with their permission.
- GET /repositories/{workspace}/{repo_slug}/permissions-config/groups (pagelen, page): Groups given access to the repository, with their permission.
- GET /workspaces/{workspace}/permissions/repositories/{repo_slug} (q, sort, pagelen, page): Everyone's effective permission on a repository, however they got it.
- GET /workspaces/{workspace}/members (pagelen, page): The workspace's members.
- GET /workspaces/{workspace}/permissions (q, pagelen, page): Each member's role in the workspace, such as owner, collaborator or member.
- GET /repositories/{workspace}/{repo_slug}/deploy-keys (pagelen, page): The repository's deploy keys, with their label and when each was last used.
- GET /repositories/{workspace}/{repo_slug}/hooks (pagelen, page): The repository's webhooks, with their events and whether each is active.
- GET /workspaces/{workspace}/hooks (pagelen, page): The workspace's webhooks, with their events and whether each is active.
- GET /repositories/{workspace}/{repo_slug}/pipelines-config/runners (pagelen, page): The repository's self-hosted runners and whether each is online.
- GET /workspaces/{workspace}/pipelines-config/runners (pagelen, page): The workspace's self-hosted runners and whether each is online.
- GET /repositories/{workspace} (q, sort, role, pagelen, page): The workspace's repositories, filtered or sorted, such as by when each was last updated.
- GET /workspaces/{workspace}/projects (pagelen, page): The workspace's projects.
