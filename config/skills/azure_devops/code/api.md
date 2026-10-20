---
name: azure_devops_api
when: A question about Azure DevOps that the other Azure DevOps tools do not answer, such as a branch's policies, a project's service connections, variable groups, agent pools, test runs, work items or a run's artifacts listed, or anything else Azure DevOps' REST API reads, and finding out whether its API offers a read at all
tools: [api_read, list_repositories]
---
`api_read` sends a GET to any path of Azure DevOps' REST API in this connection's organization and answers what Azure DevOps said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through Azure DevOps' other tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_repositories` for what this connection reads, and the pull request, pipeline, deployment and file tools for those. Reach for `api_read` for the rest.
2. Find the path in Azure DevOps' REST reference before the first call, not by guessing. Microsoft publishes it at https://learn.microsoft.com/rest/api/azure/devops with every read listed by area. Read it with the web reading tool, where the workspace allows reading the web. The reference is not copied into Firefight's documentation. When the reference lists no read for the question, Azure DevOps' API does not offer it. Say so, and give the steps in Azure DevOps instead.
3. Write the path after the organization, as the reference writes it after https://dev.azure.com/{organization}, with the project first, such as /Shop/_apis/policy/configurations. A read names a project this connection reads, unless it reads every project its token can. A read of the organization itself, such as /_apis/projects, names none. Put every parameter in `query`, never in the path. api-version is 7.1 unless `query` gives another, such as 7.1-preview.1 for a read the reference marks preview.
4. A list answers one page. Pass $top and read on with the continuationToken the reference names, or $skip.
5. Variable groups, service connections, pipeline definitions and runs come back with their variables as names and values hidden, and service hook subscriptions with their addresses cut to the host. Run logs, artifacts, file contents and secure files are not read here. Use the file tools and the job log tool in the failing pipeline skill.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /_apis/projects ($top, continuationToken): The organization's projects this token can read.
- GET /{project}/_apis/git/repositories: A project's Git repositories, with each default branch and web address.
- GET /{project}/_apis/git/repositories/{repositoryId}/refs (filter, peelTags, $top, continuationToken): A repository's branches and tags, each with the commit it points at.
- GET /{project}/_apis/git/repositories/{repositoryId}/pullrequests (searchCriteria.status, searchCriteria.targetRefName, searchCriteria.creatorId, $top, $skip): A repository's pull requests, by status, branch or who made them.
- GET /{project}/_apis/git/repositories/{repositoryId}/pullRequests/{pullRequestId}/threads: A pull request's comment threads and their status.
- GET /{project}/_apis/git/repositories/{repositoryId}/commits/{commitId}/statuses: The statuses services posted on a commit, such as a build's.
- GET /{project}/_apis/policy/configurations (policyType, $top, continuationToken): The project's branch policies, such as required reviewers and build validation.
- GET /{project}/_apis/policy/evaluations (api-version=7.1-preview.1, artifactId, includeNotApplicable, $top, $skip): How each branch policy stands on a pull request.
- GET /{project}/_apis/build/definitions (name, path, repositoryId, repositoryType, includeLatestBuilds, $top, continuationToken): The project's pipelines, by name, folder or repository.
- GET /{project}/_apis/build/definitions/{definitionId}: One pipeline, with its repository, triggers and queue status.
- GET /{project}/_apis/build/builds (definitions, branchName, statusFilter, resultFilter, reasonFilter, minTime, maxTime, queryOrder, $top, continuationToken): The project's runs, newest first, by pipeline, branch, status or result.
- GET /{project}/_apis/build/builds/{buildId}: One run, with its pipeline, branch, commit, who asked for it and its outcome.
- GET /{project}/_apis/build/builds/{buildId}/timeline: A run's stages, jobs and steps, each with its outcome, errors and log id.
- GET /{project}/_apis/build/builds/{buildId}/changes ($top, continuationToken): The commits a run built that the run before it did not.
- GET /{project}/_apis/build/builds/{buildId}/workitems ($top): The work items linked to the commits a run built.
- GET /{project}/_apis/build/builds/{buildId}/tags: The tags on a run.
- GET /{project}/_apis/pipelines (orderBy, $top, continuationToken): The project's pipelines, as the Pipelines API lists them.
- GET /{project}/_apis/pipelines/{pipelineId}/runs/{runId}: One run of a pipeline, with its state, result and the resources it ran with.
- GET /{project}/_apis/pipelines/approvals (state, approvalIds, $expand, top): The approvals runs wait on, by state, with their steps.
- GET /{project}/_apis/distributedtask/environments (name, $top, continuationToken): The project's environments.
- GET /{project}/_apis/distributedtask/environments/{environmentId} (expands): One environment, with the resources it holds.
- GET /{project}/_apis/distributedtask/environments/{environmentId}/environmentdeploymentrecords (top, continuationToken): What an environment received, newest first, with the run, stage and job of each deployment.
- GET /{project}/_apis/distributedtask/variablegroups (groupName, $top, continuationToken): The project's variable groups, with their variables as names.
- GET /{project}/_apis/serviceendpoint/endpoints (type, includeFailed): The project's service connections, with their type and address.
- GET /{project}/_apis/release/definitions (searchText, $top, continuationToken): The project's classic release pipelines.
- GET /{project}/_apis/release/releases (definitionId, statusFilter, $top, continuationToken): Classic releases, newest first, by release pipeline or status.
- GET /{project}/_apis/release/releases/{releaseId}: One classic release, with its artifacts and the state of each stage.
- GET /{project}/_apis/release/deployments (definitionId, definitionEnvironmentId, deploymentStatus, queryOrder, $top, continuationToken): Classic release deployments, newest first, by release pipeline, stage or status.
- GET /{project}/_apis/release/approvals (statusFilter, releaseIdsFilter, $top, continuationToken): Classic release approvals, such as those still pending.
- GET /{project}/_apis/test/runs (buildUri, includeRunDetails, $top, $skip): The project's test runs, by run or build.
- GET /{project}/_apis/test/runs/{runId}/results (outcomes, $top, $skip): A test run's results, by outcome.
- GET /_apis/distributedtask/pools (poolName, poolType): The organization's agent pools.
- GET /_apis/distributedtask/pools/{poolId}/agents (includeAssignedRequest, includeLastCompletedRequest): A pool's agents, whether each is online and what it is running.
- GET /{project}/_apis/wit/workitems/{id} ($expand, fields): One work item, with its fields.
