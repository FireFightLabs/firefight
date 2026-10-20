---
name: render_api
when: A question about Render that the other Render tools do not answer, such as a service's disks, custom domains, environment groups, blueprints, projects, one deploy by its id, or anything else Render's API reads, and finding out whether Render's API offers a read at all
tools: [api_read, list_resources]
---
`api_read` sends a GET to any path of Render's public API and answers what Render said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the restart, rollback and scale tools in render_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is there. Reach for `api_read` for the rest.
2. Find the path in Render's API reference before the first call, not by guessing. Render publishes it at https://api-docs.render.com/reference, with every read listed by area. Read it with the web reading tool, where the workspace allows reading the web. Render's reference is not copied into Firefight's documentation, so search_docs does not hold it. When the reference lists no read for the question, Render's API does not offer it. Say so, and give the steps in Render's dashboard instead.
3. Fill the path's ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass limit, at most 100, and to read on, pass the cursor of the last item it answered as cursor. Pass ownerId to keep a list to this connection's workspace, since a list naming another workspace is refused.
5. Environment variables, secret files and registry credentials come back as their names, with values hidden. A datastore's connection info and a Postgres export are never read. When the question needs a value, say which variable to check in Render.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /services (ownerId, name, type, environmentId, suspended, limit, cursor): The workspace's services, with each one's type, region and whether it is suspended.
- GET /services/{serviceId}: One service, with its plan, region, branch, instances and autoscaling.
- GET /services/{serviceId}/deploys (status, createdAfter, createdBefore, limit, cursor): A service's deploys, newest first, with each one's status, commit and trigger.
- GET /services/{serviceId}/deploys/{deployId}: One deploy, with its status, commit, image and when it started and finished.
- GET /services/{serviceId}/events (type, startTime, endTime, limit, cursor): A service's events, such as deploys, failures, restarts and scaling, between two times.
- GET /events/{eventId}: One event, with its type and details such as why an instance failed.
- GET /services/{serviceId}/instances: A service's running instances and when each was made.
- GET /services/{serviceId}/jobs (status, createdAfter, limit, cursor): One-off jobs run on a service, with each one's status and timing.
- GET /services/{serviceId}/jobs/{jobId}: One job, with its command, status and when it started and finished.
- GET /logs (ownerId, resource, startTime, endTime, level, type, text, statusCode, path, limit): Log lines of services or datastores between two times, narrowed by level, text, status or path.
- GET /metrics/cpu (resource, startTime, endTime, resolutionSeconds, instance): CPU use of a service or datastore over time, per instance.
- GET /metrics/memory (resource, startTime, endTime, resolutionSeconds, instance): Memory use of a service or datastore over time, per instance.
- GET /metrics/http-requests (resource, startTime, endTime, path, aggregateBy): A service's request count over time, split by status code or host.
- GET /metrics/http-latency (resource, startTime, endTime, path, quantile): A service's response time over time at a percentile.
- GET /metrics/instance-count (resource, startTime, endTime): How many instances a service ran over time.
- GET /metrics/disk-usage (resource, startTime, endTime): Disk use of a service or datastore over time.
- GET /metrics/active-connections (resource, startTime, endTime): Open connections to a Postgres or Key Value instance over time.
- GET /metrics/replication-lag (resource, startTime, endTime): How far a Postgres read replica is behind over time.
- GET /services/{serviceId}/custom-domains (verificationStatus, limit, cursor): A service's custom domains and whether each is verified.
- GET /services/{serviceId}/custom-domains/{customDomainNameOrID}: One custom domain, with its verification status and DNS target.
- GET /services/{serviceId}/env-vars (limit, cursor): A service's environment variables by name, never their values.
- GET /services/{serviceId}/secret-files (limit, cursor): A service's secret files by name, never their contents.
- GET /env-groups (ownerId, environmentId, name, limit, cursor): The workspace's environment groups by name and the services linked to each.
- GET /postgres (ownerId, environmentId, suspended, limit, cursor): The workspace's Postgres instances, with each one's plan, version and status.
- GET /postgres/{postgresId}: One Postgres instance, with its plan, version, storage, replicas and status.
- GET /postgres/{postgresId}/recovery: A Postgres instance's point-in-time recovery window.
- GET /postgres/{postgresId}/query/top-queries: The queries taking the most time on a Postgres instance.
- GET /postgres/{postgresId}/query/processes: The queries running on a Postgres instance now.
- GET /key-value (ownerId, environmentId, limit, cursor): The workspace's Key Value instances, with each one's plan and status.
- GET /key-value/{redisId}: One Key Value instance, with its plan, version, eviction policy and status.
- GET /disks (ownerId, serviceId, limit, cursor): The workspace's persistent disks, with each one's size and service.
- GET /disks/{diskId}/snapshots: A disk's snapshots and when each was taken.
- GET /owners/{ownerId}/audit-logs (startTime, endTime, limit, cursor): The workspace's audit log, who changed what and when, between two times.
- GET /owners/{ownerId}/members: The workspace's members and their roles.
- GET /projects (ownerId, name, limit, cursor): The workspace's projects.
- GET /environments (ownerId, projectId, limit, cursor): A project's environments.
- GET /maintenance (ownerId, resourceId, state): Maintenance Render has run or scheduled on the workspace's resources.
- GET /notification-settings/overrides (ownerId, serviceId, limit, cursor): Services whose failure notifications differ from the workspace's.
