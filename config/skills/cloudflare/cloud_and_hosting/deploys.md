---
name: cloudflare_deploys
when: A Cloudflare Worker or Pages project broke after a deploy or build, a build failed or is stuck, or a Worker's traffic should be moved between versions, rolled back, split or a Pages deployment tried again
tools: [get_resource_map, resource_status, recent_deploys, run_history, search_logs, rollback, execute, search]
---
Start from the Worker or Pages project on the resource map with `get_resource_map`. It names the account id every path below takes, and `resource_status` reads how it is set up now.

1. See what changed. `recent_deploys` lists a Worker's deployments with the share of traffic each version gets, and its newest versions, including any uploaded and never deployed. For a Pages project it lists deployments with their commit and status.
2. Follow the builds. `run_history` lists a Worker's Workers Builds and a Pages project's deployments, each with its status and how long it took, and follows one by its id. `search_logs` with `stream` build reads a build's log, of the newest build or the one named in `deployment`.
3. Put it back. `rollback` sends all of a Worker's traffic to the version named, or rolls a Pages project back to the deployment named. Both ask the person first.
4. Try a Pages deployment again when it failed for something outside its code, such as a timeout or a dependency that could not be fetched: `execute` with POST /accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}/retry. It runs that deployment again, and asks the person first.
5. Stop a Workers build that is queued or running and should not deploy: `execute` with PUT /accounts/{account_id}/builds/builds/{build_uuid}/cancel, the build id from `run_history`. Say which commit it was building, since that change will not go out. It asks the person first.
6. Split a Worker's traffic between two versions, to send a share to a fix or to step back from a bad version gradually: `execute` with POST /accounts/{account_id}/workers/scripts/{script_name}/deployments and body {"strategy": "percentage", "versions": [{"version_id": "<new>", "percentage": 10}, {"version_id": "<current>", "percentage": 90}], "annotations": {"workers/message": "<why, and that Firefight made it>"}}. The percentages add up to 100. A split stays as it is until another deployment changes it, so holding a rollout needs nothing, and moving on is the same request with new shares. It asks the person first.
7. After any of these, follow it with `run_history` or `recent_deploys`, and say what is serving now.
