---
name: tinybird_deployments
when: Something in a Tinybird workspace broke after a deployment, a deployment failed or is stuck, or the person asks what changed in the workspace
tools: [recent_deploys, jobs, search_errors, resource_status, list_endpoints, list_datasources]
---
In Tinybird a deployment builds the new version of the project beside the live one, as a staging deployment, and promoting it makes it live. A deployment that fails, or that the team discards, never replaces the live one, which keeps serving.

1. Call `recent_deploys` to list the deployments, newest first, with their status and when each started and ended. Note the one that went live last, and any still waiting or working.
2. Compare its time with when the trouble began. Errors that began right after a deployment finished are the first thing to tie to it, so call `search_errors` from shortly before it.
3. A deployment that failed carries its error. Read the jobs around it with `jobs` and `status` set to error, since a deployment that changes a data source may also run populate jobs that backfill it, and those can fail on their own.
4. A deployment still working for a long time is usually backfilling a large data source. Call `jobs` with `job_type` set to populate to see what it is waiting on.
5. Call `resource_status` for the endpoints and data sources the person mentioned, or name them with `list_endpoints` and `list_datasources`, to see how each stands now.

Tinybird has no rollback of a live deployment. Undoing one means deploying the earlier version of the project again, and an unfinished deployment is cancelled with tb deployment discard, which keeps the previous live deployment. Both are for the team to run.
