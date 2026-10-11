---
name: google_cloud_api
when: A question about Google Cloud that the other Google Cloud tools do not answer, such as a Cloud Run revision's conditions, GKE node pools, Cloud SQL operations and backups, Pub/Sub subscriptions, Artifact Registry images, DNS records, IAM policies, or anything else Google Cloud's APIs read, and finding out whether an API offers a read at all
tools: [api_read, list_resources, run_history, list_builds]
references: [api/run/index.md, api/compute/index.md, api/sqladmin/index.md, api/container/index.md, api/cloudbuild/index.md, api/clouddeploy/index.md, api/logging/index.md, api/monitoring/index.md, api/cloudresourcemanager/index.md, api/iam/index.md, api/secretmanager/index.md, api/pubsub/index.md, api/artifactregistry/index.md, api/cloudfunctions/index.md, api/redis/index.md, api/dns/index.md, api/storage/index.md]
---
`api_read` sends a GET to one of Google Cloud's APIs and answers what Google said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, scale and restart tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is on the map, and `list_builds` for Cloud Build builds and their steps. Reach for `api_read` for the rest.
2. Find the path in the API's reference before the first call, not by guessing: read api/<api>/index.md for the API (use_skill with this skill and that reference), such as api/cloudbuild/index.md, which lists every read it offers with its path, parameters and what it answers. When no reference lists a read for the question, Google Cloud's API does not offer one. Say so, and give the steps in the console instead.
3. Set `service` to the API's name, the first part of its googleapis.com host, such as cloudbuild or run, and `path` to the path as the reference writes it with its ids filled in, such as /v1/projects/<project>/locations/<region>/builds. Put every parameter in `query`, never in the path. A path names one of this connection's projects, and another project is refused.
4. A list answers one page. Pass pageSize, and to read on, pass the nextPageToken it answered as pageToken. Narrow a list with its filter where the reference gives one.
5. A secret's value is never read, nor a stored object's contents. Environment variables and an instance's metadata come back as their names. Say which name to check in the console when the question needs a value.
6. A refusal for want of a permission is the workspace's to fix in IAM. Name the permission Google's refusal gives, such as cloudbuild.builds.list, and the role that holds it, such as Cloud Build Viewer.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- run: GET /v2/projects/{projectsId}/locations/{locationsId}/services (pageSize, pageToken): Cloud Run services in a region with their latest revision and traffic.
- run: GET /v2/projects/{projectsId}/locations/{locationsId}/services/{servicesId}: One Cloud Run service with its conditions, traffic and scaling.
- run: GET /v2/projects/{projectsId}/locations/{locationsId}/services/{servicesId}/revisions (pageSize, pageToken): A service's revisions with their image, conditions and readiness.
- run: GET /v2/projects/{projectsId}/locations/{locationsId}/jobs/{jobsId}/executions (pageSize, pageToken): A Cloud Run job's runs with how many tasks succeeded and failed.
- cloudbuild: GET /v1/projects/{projectsId}/locations/{locationsId}/builds (filter, pageSize, pageToken): Builds in a region, newest first, filtered by status or trigger.
- cloudbuild: GET /v1/projects/{projectsId}/locations/{locationsId}/builds/{buildsId}: One build with its status, steps, commit and log address.
- clouddeploy: GET /v1/projects/{projectsId}/locations/{locationsId}/deliveryPipelines (filter, pageSize, pageToken): Cloud Deploy pipelines with their stages and targets.
- clouddeploy: GET /v1/projects/{projectsId}/locations/{locationsId}/deliveryPipelines/{deliveryPipelinesId}/releases (filter, pageSize, pageToken): A pipeline's releases with their render state and when each was made.
- clouddeploy: GET /v1/projects/{projectsId}/locations/{locationsId}/deliveryPipelines/{deliveryPipelinesId}/releases/{releasesId}/rollouts (filter, pageSize, pageToken): A release's rollouts with their state and failure reason.
- container: GET /v1/projects/{projectsId}/locations/{locationsId}/clusters: GKE clusters with their version and status, in every location when the location is a hyphen.
- container: GET /v1/projects/{projectsId}/locations/{locationsId}/clusters/{clustersId}: One GKE cluster with its status, version and conditions.
- container: GET /v1/projects/{projectsId}/locations/{locationsId}/clusters/{clustersId}/nodePools: A cluster's node pools with their machine type, size and status.
- sqladmin: GET /v1/projects/{project}/instances (filter, maxResults, pageToken): Cloud SQL instances with their state, version, tier and region.
- sqladmin: GET /v1/projects/{project}/instances/{instance}: One Cloud SQL instance with its settings, flags and maintenance.
- sqladmin: GET /v1/projects/{project}/instances/{instance}/backupRuns (maxResults, pageToken): An instance's backups with their status and when each ran.
- sqladmin: GET /v1/projects/{project}/operations (instance, maxResults, pageToken): Cloud SQL operations such as restarts and failovers, newest first.
- monitoring: GET /v3/projects/{projectsId}/timeSeries (filter, interval.startTime, interval.endTime, aggregation.alignmentPeriod, aggregation.perSeriesAligner, aggregation.crossSeriesReducer, view, pageSize, pageToken): A metric's values over a time range, filtered to one resource.
- monitoring: GET /v3/projects/{projectsId}/alertPolicies (filter, pageSize, pageToken): Alerting policies with their conditions and whether each is on.
- monitoring: GET /v3/projects/{projectsId}/alerts (filter, pageSize, pageToken): Alerts that fired, open or closed, with their policy and resource.
- monitoring: GET /v3/projects/{projectsId}/uptimeCheckConfigs (filter, pageSize, pageToken): Uptime checks with what each one checks and how often.
- compute: GET /compute/v1/projects/{project}/aggregated/instances (filter, maxResults, pageToken): Every VM across zones, with its status and machine type.
- compute: GET /compute/v1/projects/{project}/aggregated/instanceGroupManagers (filter, maxResults, pageToken): Managed instance groups with their size and current actions.
- compute: GET /compute/v1/projects/{project}/aggregated/backendServices (filter, maxResults, pageToken): Load balancer backends and their health checks.
- compute: GET /compute/v1/projects/{project}/aggregated/sslCertificates (filter, maxResults, pageToken): Load balancer certificates with their domains, status and expiry.
- compute: GET /compute/v1/projects/{project}/global/firewalls (filter, maxResults, pageToken): VPC firewall rules with what each one allows or denies.
- cloudresourcemanager: GET /v3/projects/{projectsId}: One project with its state, parent and labels.
- iam: GET /v1/projects/{projectsId}/serviceAccounts (pageSize, pageToken): The project's service accounts and whether each is switched off.
- iam: GET /v1/projects/{projectsId}/serviceAccounts/{serviceAccountsId}/keys (keyTypes): A service account's keys with their validity dates, never the key.
- dns: GET /dns/v1/projects/{project}/managedZones (maxResults, pageToken): The project's Cloud DNS zones.
- dns: GET /dns/v1/projects/{project}/managedZones/{managedZone}/rrsets (name, type, maxResults, pageToken): The DNS records in one zone.
- secretmanager: GET /v1/projects/{projectsId}/secrets (filter, pageSize, pageToken): Secrets by name, never their values.
- secretmanager: GET /v1/projects/{projectsId}/secrets/{secretsId}/versions (filter, pageSize, pageToken): A secret's versions with their state, never their values.
- cloudfunctions: GET /v2/projects/{projectsId}/locations/{locationsId}/functions (filter, pageSize, pageToken): Cloud Functions with their state, runtime and last update.
