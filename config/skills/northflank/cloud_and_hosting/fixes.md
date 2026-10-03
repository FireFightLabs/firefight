---
name: northflank_fixes
when: Writing or applying a fix that changes anything in a Northflank project, such as a restart, a scale, a pause, a rollback to an earlier build, or any other call Northflank's API offers
tools: [api_request, resource_status, recent_builds, recent_deploys, list_resources]
---
`api_request` reaches all of Northflank's API inside the project, with the method, path and body Northflank's API docs give for the call, the path written after /v1/projects/<project>/. A change goes through it as one step of a fix. While investigating it only takes GET. Each step says how to undo it. Use ids as `list_resources` shows them. GET reads anything the other tools do not cover.

1. Read what is there first. `resource_status` gives the service's instances, plan and what it deploys, and `recent_deploys` what ran when. The undo comes from these values.
2. Pick the change:
   - Restart, for a service stuck in a bad state while its code is fine: `method` POST, `path` services/<id>/restart, no body. Nothing to undo.
   - Scale, for load the service cannot keep up with: `method` POST, `path` services/<id>/scale, `body` with instances (a number) or deploymentPlan (a plan id). Undo by scaling back to the instances and plan `resource_status` showed.
   - Roll back to an earlier build, when a deployment broke it: find the last good build with `recent_builds` on the service that builds the code, then `method` POST, `path` services/<id>/deployment, `body` {"internal": {"id": "<service that builds it>", "buildId": "<build id>"}}. For a service that builds its own code, that is the service itself. Undo by deploying the build that was live before, from `recent_deploys`.
   - Pause, to stop a service doing harm: `method` POST, `path` services/<id>/pause, no body. Undo with `method` POST, `path` services/<id>/resume, and a `body` with instances when it should come back at a set count.
3. Anything else Northflank's API offers is reachable the same way, such as jobs, volumes, domains, pipelines and secret groups. A DELETE removes what it names for good, a database with its data, so say what is lost in the step and that it cannot be undone.
4. Secret values never come back. Reading an environment, build arguments or a secret group returns the names with the values hidden, and a body that looks like it holds a credential is refused. Northflank sets a service's whole environment at once, so a change to environment variables would drop the values you cannot see. Make it a step for a person that names the variable and the value to set, without the value when it is a secret.
5. When the change is defined as code, such as a Terraform or Pulumi project, or the service's settings in a repository, the fix is a pull request to that code instead, since the next apply would undo a change made here.
6. A refusal that says the token's role cannot make the change is the workspace's to fix in Northflank. Say so in the step, and keep the rest of the fix.
