---
name: google_cloud_api
when: A question about Google Cloud that the other Google Cloud tools do not answer, such as a Cloud Build build and its steps, a Cloud Deploy release or rollout, a Cloud Run revision's conditions, GKE node pools, Cloud SQL operations and backups, Pub/Sub subscriptions, Artifact Registry images, DNS records, IAM policies, or anything else Google Cloud's APIs read, and finding out whether an API offers a read at all
tools: [api_read, list_resources]
references: [api/run/index.md, api/compute/index.md, api/sqladmin/index.md, api/container/index.md, api/cloudbuild/index.md, api/clouddeploy/index.md, api/logging/index.md, api/monitoring/index.md, api/cloudresourcemanager/index.md, api/iam/index.md, api/secretmanager/index.md, api/pubsub/index.md, api/artifactregistry/index.md, api/cloudfunctions/index.md, api/redis/index.md, api/dns/index.md, api/storage/index.md]
---
`api_read` sends a GET to one of Google Cloud's APIs and answers what Google said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, scale and restart tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is on the map. Reach for `api_read` for the rest.
2. Find the path in the API's reference before the first call, not by guessing: read api/<api>/index.md for the API (use_skill with this skill and that reference), such as api/cloudbuild/index.md, which lists every read it offers with its path, parameters and what it answers. When no reference lists a read for the question, Google Cloud's API does not offer one. Say so, and give the steps in the console instead.
3. Set `service` to the API's name, the first part of its googleapis.com host, such as cloudbuild or run, and `path` to the path as the reference writes it with its ids filled in, such as /v1/projects/<project>/locations/<region>/builds. Put every parameter in `query`, never in the path. A path names one of this connection's projects, and another project is refused.
4. A list answers one page. Pass pageSize, and to read on, pass the nextPageToken it answered as pageToken. Narrow a list with its filter where the reference gives one.
5. A secret's value is never read, nor a stored object's contents. Environment variables and an instance's metadata come back as their names. Say which name to check in the console when the question needs a value.
6. A refusal for want of a permission is the workspace's to fix in IAM. Name the permission Google's refusal gives, such as cloudbuild.builds.list, and the role that holds it, such as Cloud Build Viewer.
