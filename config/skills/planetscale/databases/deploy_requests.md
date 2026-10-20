---
name: planetscale_deploy_requests
when: A schema change on a PlanetScale database may be behind the problem, a deploy request failed or is stuck, or the person wants one reverted, cancelled or cut over
tools: [run_history, recent_deploys, planetscale_list_deploy_requests, planetscale_get_deploy_request, rollback, planetscale_cancel_deploy_request, planetscale_skip_revert_period, planetscale_force_cutover, planetscale_apply_deploy_request, planetscale_complete_errored_deploy]
---
Deploy requests are how a schema change reaches a PlanetScale database's production branch. Each one has a number, the branch it deploys and the branch it deploys into. PlanetScale sends deploy request events for Vitess (MySQL) databases only, while the reads work for any.

1. Call `recent_deploys` for the database or its branch for the deploy requests deployed into it, newest first, with when each finished. One deployed just before the problem began is the first suspect.
2. Call `run_history` for the database to see every deploy request, open ones included, and how long finished ones usually take. With `run` set to a number, it follows that one deploy request, each schema change a step.
3. Call `planetscale_get_deploy_request` with its `number` to read why one failed or what it waits for: every schema change with its DDL, its state and the error PlanetScale gave, the lint errors that stop it, and whether its revert window is open.
4. When the person agrees, act on it, each change asked for on its own:
   - `rollback` with `to` set to the deploy request's number puts the schema back, only while its revert window is open.
   - `planetscale_cancel_deploy_request` takes one out of the deploy queue before it runs.
   - `planetscale_force_cutover` cuts over one waiting for its cutover now.
   - `planetscale_apply_deploy_request` applies one made with gated deployments once it is ready.
   - `planetscale_complete_errored_deploy` keeps the schema changes that applied from one that errored.
   - `planetscale_skip_revert_period` closes the revert window, after which it can no longer be reverted, so say that before asking.
5. These tools reach PlanetScale's API. A connection made with a service token needs the token's id on its connect form for them, and the tool says so when it is missing.
