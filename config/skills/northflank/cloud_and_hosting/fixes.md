---
name: northflank_fixes
when: Writing or applying a fix that changes anything in a Northflank project, such as a restart, a scale, a pause, a rollback to an earlier build, creating or changing a pipeline or release flow, or any other call to Northflank's API, reading a whole list page by page, and finding out whether Northflank's API offers a call at all
tools: [api_request, resource_status, recent_builds, recent_deploys, list_resources]
references: [api/index.md, api/project/addons.md, api/project/jobs.md, api/project/pipelines.md, api/project/preview-blueprints.md, api/project/secrets.md, api/project/services.md, api/project/volumes.md, api/project/workflows.md]
---
`api_request` reaches Northflank's API inside the project, the path written after /v1/projects/<project>/. Every call Northflank's API offers is in the API reference with this skill, written out from Northflank's own API client. Before any call this skill does not give, read api/index.md (use_skill with this skill and that reference), then the area's file it names, such as api/project/pipelines.md, for the body the call needs. Look there before searching the web. Query options go in `query`, never in the path, and only the ones the reference lists under Query for that call, which `api_request` checks. A list answers one page, with its pagination first. To read all of it, pass per_page 100 in `query`, and while the pagination says hasNextPage is true, call again with cursor set to the cursor it gave. Narrow a list with the filters its call lists instead of reading every page, such as status and concluded for a release flow's runs, or runId for a job's containers. A change goes through it as one step of a fix. While investigating it only takes GET. Each step says how to undo it. Use ids as `list_resources` shows them. GET reads anything the other tools do not cover.

1. Read what is there first. `resource_status` gives the service's instances, plan and what it deploys, and `recent_deploys` what ran when. The undo comes from these values.
2. Pick the change:
   - Restart, for a service stuck in a bad state while its code is fine: `method` POST, `path` services/<id>/restart, no body. Nothing to undo.
   - Restart a database stuck in a bad state: `method` POST, `path` addons/<id>/restart, no body.
   - Scale, for load the service cannot keep up with: `method` POST, `path` services/<id>/scale, `body` with instances (a number) or deploymentPlan (a plan id). Undo by scaling back to the instances and plan `resource_status` showed. A database scales with `path` addons/<id>/scale and replicas, storage (in MB) or deploymentPlan, and its storage and replicas can only grow. A job runs one container a run, so it scales only by its plan: `path` jobs/<id>/scale, `body` {"deploymentPlan": "<plan id>"}.
   - Roll back to an earlier build, when a deployment broke it: find the last good build with `recent_builds` on the service that builds the code, then `method` POST, `path` services/<id>/deployment, `body` {"internal": {"id": "<service that builds it>", "buildId": "<build id>"}}. For a service that builds its own code, that is the service itself. Undo by deploying the build that was live before, from `recent_deploys`.
   - Roll back a service that runs an image from a registry, which `resource_status` shows as Runs the image: deploy the image that was live before, from `recent_deploys`, with `method` POST, `path` services/<id>/deployment, `body` {"external": {"imagePath": "<image and tag>", "credentials": "<the saved credentials it used, if any>"}}. Undo by deploying the image it runs now.
   - During a canary rollout, which `recent_deploys` shows as a stable and a canary side, a new deployment may be blocked until the rollout ends. To give up the canary, end the rollout and go back to a deployment with `method` POST, `path` services/<id>/rollout/rollback, `body` {"deployment": "<the stable deployment's id>"}. To keep the canary, promote it with `method` POST, `path` services/<id>/rollout/promote, no body. GET services/<id>/rollout says whether one is under way.
   - Pause, to stop a service doing harm: `method` POST, `path` services/<id>/pause, no body. Undo with `method` POST, `path` services/<id>/resume, and a `body` with instances when it should come back at a set count.
3. Anything else the reference lists inside the project is reachable the same way, such as jobs, volumes, secret groups, a pipeline's release flows and stopping a workflow or release run, which the northflank_workflows skill gives. A release flow's own roll back to an earlier release is only in Northflank's dashboard, with no call in its API, so roll back the service it released as above, or make it a step for a person there. A path the reference lists outside the project, such as domains, templates or the team's settings, cannot be reached with `api_request`, so it is a step for a person. When the reference does not list an operation, Northflank's API does not offer it. Say so plainly, and give the steps in Northflank's dashboard, or in a Northflank template where the team keeps its setup as code, rather than trying other paths. A DELETE removes what it names for good, a database with its data, so say what is lost in the step and that it cannot be undone.
4. Creating a pipeline is one of those. The API lists and reads pipelines, and has no call that creates one. In the dashboard, open the project's Pipelines and create a new one (or Pipeline from the Create new menu), name it, and add each service, job or database to its stage, such as Production. A service or job that builds straight from a Git repository cannot join a pipeline, only one that deploys from a build service or an image. A template can hold a pipeline node instead. Once the pipeline exists, its release flow for a stage is added in the dashboard from the stage's release header, or read with GET and set with POST at pipelines/<pipeline>/release-flows/<stage>, whose body is the flow as a template (apiVersion and spec).
5. Secret values never come back. Reading an environment, build arguments or a secret group returns the names with the values hidden, and a body that looks like it holds a credential is refused. Northflank sets a service's whole environment at once, so a change to environment variables would drop the values you cannot see. Make it a step for a person that names the variable and the value to set, without the value when it is a secret.
6. When the change is defined as code, such as a Terraform or Pulumi project, or the service's settings in a repository, the fix is a pull request to that code instead, since the next apply would undo a change made here.
7. A refusal that says the token's role cannot make the change is the workspace's to fix in Northflank. Say so in the step, and keep the rest of the fix.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET services (per_page, cursor): Every service in the project, with its type and status.
- GET services/{serviceId}: One service, with its status, deployment, ports and resource plan.
- GET services/{serviceId}/deployment: What a service runs now, its image or build, its instances and plan.
- GET services/{serviceId}/deployments (releaseType, per_page, cursor): A service's deployment history, newest first.
- GET services/{serviceId}/rollout: A service's rollout in progress, with its stage and status.
- GET services/{serviceId}/build (per_page, cursor): A service's builds, with each one's status, commit and when it ran.
- GET services/{serviceId}/build/{buildId}: One build of a service, with its status, commit and timing.
- GET services/{serviceId}/containers (per_page, cursor): A service's containers, with each one's status, restarts and when it started.
- GET services/{serviceId}/health-checks: A service's health checks, their paths, ports and thresholds.
- GET services/{serviceId}/ports: A service's ports, their protocols, public addresses and custom domains.
- GET jobs (per_page, cursor): Every job in the project, cron and manual.
- GET jobs/{jobId}: One job, with its schedule, status and settings.
- GET jobs/{jobId}/runs (per_page, cursor): A job's runs, with each one's status and when it started and finished.
- GET jobs/{jobId}/runs/{runId}: One run of a job, with its status, exit and timing.
- GET jobs/{jobId}/containers (runId, per_page, cursor): A job's containers, narrowed to one run, with each one's status.
- GET jobs/{jobId}/deployment: What a job runs now, its image or build and plan.
- GET jobs/{jobId}/build (per_page, cursor): A job's builds, with each one's status and commit.
- GET jobs/{jobId}/build/{buildId}: One build of a job, with its status, commit and timing.
- GET jobs/{jobId}/health-checks: A job's health checks and their thresholds.
- GET addons (per_page, cursor): Every addon in the project, such as Postgres or Redis, with its status.
- GET addons/{addonId}: One addon, with its type, version, status and resources.
- GET addons/{addonId}/containers (per_page, cursor): An addon's containers, with each one's status and restarts.
- GET addons/{addonId}/version: An addon's version and the versions it can move to.
- GET addons/{addonId}/backups (per_page, cursor): An addon's backups, with each one's status and when it was taken.
- GET addons/{addonId}/backups/{backupId}: One backup of an addon, with its status, size and timing.
- GET addons/{addonId}/backup-schedules (per_page, cursor): An addon's backup schedules and how long backups are kept.
- GET addons/{addonId}/restores (per_page, cursor): Restores run on an addon, with each one's status.
- GET pipelines (per_page, cursor): Every pipeline in the project.
- GET pipelines/{pipelineId}: One pipeline, with the services and jobs in each stage.
- GET pipelines/{pipelineId}/release-flows/{stage}/runs (status, concluded, per_page, cursor): A pipeline stage's release flow runs, with each one's status.
- GET pipelines/{pipelineId}/release-flows/{stage}/runs/{runId}: One release flow run, with its steps and their status.
- GET workflows (per_page, cursor): Every workflow in the project.
- GET workflows/{workflowId}/runs (per_page, cursor): A workflow's runs, with each one's status.
- GET workflows/{workflowId}/runs/{runId}: One workflow run, with its steps and their status.
- GET volumes (per_page, cursor): Every volume in the project, with its size and what it is attached to.
- GET volumes/{volumeId}: One volume, with its size, storage class and attached service.
- GET volumes/{volumeId}/backups (per_page, cursor): A volume's backups, with each one's status and when it was taken.
- GET secrets (per_page, cursor): The project's secret groups by name, type and priority, never their values.
