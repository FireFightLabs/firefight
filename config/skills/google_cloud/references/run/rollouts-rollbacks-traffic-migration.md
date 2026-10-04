Cloud Run lets you specify which revisions should receive traffic
and to specify traffic percentages that are received by a revision. This
feature lets you rollback to a previous revision, gradually deploy a
revision, and split traffic between
multiple revisions. This page describes how to use this feature to manage
traffic to your Cloud Run revisions.

Note that traffic routing adjustments are not instantaneous. When you change traffic for
revisions, all requests being processed will continue to completion. In flight
requests won't be dropped and may be directed to either a new revision or a previous
revision during the transition period.

## Traffic splitting and session affinity

If you are splitting traffic between multiple revisions with
session affinity enabled, see [Session affinity and traffic splitting](https://docs.cloud.google.com/run/docs/configuring/session-affinity#affinity-and-traffic-splitting)
for details on the effect of session affinity on traffic splitting.

## Lifecycle of traffic splits

If you split traffic between multiple revisions or assigned traffic to a previous revision,
all subsequent deployments use that traffic split pattern going forward. To return to
just using the latest revision without traffic splitting,
[send all traffic to the latest revision](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration#send-to-latest).

## Required roles

To get the permissions that you need to manage Cloud Run services and
revisions, ask your administrator to grant you the following IAM
roles:

- If you are managing a service that was deployed from a container image:
  - [Cloud Run Developer](https://docs.cloud.google.com/iam/docs/roles-permissions/run#run.developer) (`roles/run.developer`) on the Cloud Run service
  - [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) (`roles/iam.serviceAccountUser`) on the service identity
  - [Artifact Registry Reader](https://docs.cloud.google.com/iam/docs/roles-permissions/artifactregistry#artifactregistry.reader) (`roles/artifactregistry.reader`) on the Artifact Registry repository of the container images of the service (if applicable)
- If you are managing a service that was deployed from source code:
  - [Cloud Run Source Developer](https://docs.cloud.google.com/iam/docs/roles-permissions/run#run.sourceDeveloper) (`roles/run.sourceDeveloper`) on your project
  - [Service Usage Consumer](https://docs.cloud.google.com/iam/docs/roles-permissions/serviceusage#serviceusage.serviceUsageConsumer) (`roles/serviceusage.serviceUsageConsumer`) on your project
  - [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) (`roles/iam.serviceAccountUser`) on the service identity
  - Additionally, grant the [Cloud Run Builder](https://docs.cloud.google.com/iam/docs/roles-permissions/run#run.builder) (`roles/run.builder`) role to the Cloud Build service account on the project. The build service account is responsible for building your service, and defaults to the Compute Engine default service account.

For a list of IAM roles and permissions that are associated with
Cloud Run, see
[Cloud Run IAM roles](https://docs.cloud.google.com/run/docs/reference/iam/roles)
and [Cloud Run IAM permissions](https://docs.cloud.google.com/run/docs/reference/iam/permissions).
If your Cloud Run service interfaces with
Google Cloud APIs, such as Cloud Client Libraries, see the
[service identity configuration guide](https://docs.cloud.google.com/run/docs/configuring/services/service-identity).
For more information about granting roles, see
[deployment permissions](https://docs.cloud.google.com/run/docs/reference/iam/roles#additional-configuration)
and [manage access](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access).

## Roll back to a previous revision

To roll back to a previous revision:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Locate the service in the services list, and click it.

3. Click the **Revision history** tab to show the list of current revisions
   for that service.

4. In the list of revisions, click the ellipsis icon to the right of the
   revision you are rolling back:

5. Click **Manage traffic** to display the manage traffic options.

6. Select **Send all traffic to one revision** and select the revision from
   the drop-down.

7. Click **Save**.

### gcloud

Use the following command:

<br />

```bash
gcloud run services update-traffic SERVICE --to-revisions REVISION=100
```

<br />

- Replace <var translate="no">SERVICE</var> with the name of the service.
- Replace <var translate="no">REVISION</var> with the name of the revision you are rolling back to.

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Below the `spec` attribute, locate and update the `traffic` attribute to
   the following:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION
           percent: 100

   Replace
   - <var translate="no">REVISION</var> with the name of the revision you are rolling back to.
3. Replace the service with its new configuration using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```
4. Wait for the update to complete: you should see a message that the
   revision you are rolling back *from* has been deployed and is serving
   `0` percent of traffic.

### Terraform


To learn how to apply or remove a Terraform configuration, see
[Basic Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands).
Add the following to a [`google_cloud_run_v2_service`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) resource in your Terraform configuration:  

<br />

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {}

      traffic {
        percent = 100
        # This revision needs to already exist
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"

      }
    }

> [!NOTE]
> **Note:** If the revision doesn't exist, you will receive the error: `Error creating Service: googleapi: Error 400: spec.template.spec: Revision template was empty`.

## Gradual roll out for revisions

To roll out a new revision gradually:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Select a service in the services list.

3. Configure your service as needed.

4. Click **View diff and redeploy**.

5. Make sure that **Serve this revision immediately** is not selected.

6. Click **Deploy changes**.

7. Click the **Revision history** tab. If the new revision is not listed
   yet, click the refresh button.

8. In the list of revisions, click the ellipsis icon to the right of the
   revision you are rolling out to.

9. Click **Manage traffic** to display the manage traffic options.

10. Click **Split traffic across multiple revisions**.

11. Select the revisions you want to split traffic between and the percentage
    of traffic for each revision.

12. Click **Save**.

### gcloud

To deploy a service from a container image:

1. Deploy the revision you want to roll out gradually, initially setting
   it to receive no traffic:

   - To deploy a service from source code:

     ```bash
     gcloud run deploy --image IMAGE --no-traffic
     ```

     Replace <var translate="no">IMAGE</var> with the image you are deploying.
   - To deploy a service from source code:

     ```bash
     gcloud run deploy SERVICE --source . --no-traffic
     ```

     Replace <var translate="no">SERVICE</var> with the name of your service.
2. Specify the percentage of traffic you want the new revision to handle,
   for example, 5 percent:

   ```bash
   gcloud run services update-traffic SERVICE --to-revisions REVISION=PERCENTAGE
   ```
   - Replace <var translate="no">SERVICE</var> with the name of the service.
   - Replace <var translate="no">REVISION</var> with the name of the revision you are rolling out gradually. To specify the latest revision, you can use `LATEST`, for example, `LATEST=5`.
   - Replace <var translate="no">PERCENTAGE</var> with the percentage of traffic you want to send to the new revision, for example, `5` to send it 5% of traffic.
3. After the revision's performance is satisfactory, repeat the preceding
   `update-traffic` step, but increase the percentage value as desired.

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Make any desired configuration changes to the service, and specify the
   revision name you want for the new revision:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
        template:
          metadata:
            annotations:
            ...
            name: REVISION-NAME

   Replace
   - <var translate="no">REVISION-NAME</var> with the name you want the new revision to have.
3. Below the `spec` attribute, locate
   and update the `traffic` attribute so that the new revision serves only a
   small amount of traffic:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION-NEW
           percent: PERCENT-NEW
         - revisionName: REVISION-FORMER
           percent: PERCENT-FORMER

   Note that the percentages must add up to 100. Replace
   - <var translate="no">REVISION-NEW</var> with the name of the revision you are rolling out gradually.
   - <var translate="no">REVISION-FORMER</var> with the name of the serving revision.
   - <var translate="no">PERCENT-NEW</var> with the traffic percentage you want to send to the new revision, for example use `10` to send 10% of the traffic to that revision.
   - <var translate="no">PERCENT-FORMER</var> with the traffic percentage you want to send to the old revision
4. Wait for the update to complete: you should see a message that the
   new revision you are gradually rolling out has been deployed and is serving
   the traffic percentage value you used.

### Terraform

Add the following to your `.tf` file and gradually update the traffic percentage from previous revision to the [latest revision](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#latest_ready_revision).
Keep in mind that every traffic change will require another `terraform apply` to be executed.

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {
        containers {
          # Image or image tag must be different from previous revision
          image = "us-docker.pkg.dev/cloudrun/container/hello"
        }
      }

      # Define the traffic split for each revision
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#traffic
      traffic {
        percent = 100
        # This revision needs to already exist
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }

      traffic {
        # Deploy new revision with 0% traffic
        percent = 0
        type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
      }
    }

Apply the changes by entering `terraform apply`.

## Split traffic between multiple revisions

To split traffic between two or more revisions:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Locate the service in the services list, and click it.

3. Click the **Revision history** tab.

4. Click **Manage traffic**.

5. The currently serving new revision is listed. In the form:

   1. Set the currently serving revision percentage to the chosen split.
   2. Select one of the previous revisions using the list and set it to the chosen percentage split.
   3. To split traffic between more revisions, click **Add Revision**, select the revision, and set the percentage to the chosen split.
   4. Click **Save**.

### gcloud

Specify the revisions and the percentage of traffic for each revision in a
comma delimited list:

<br />

```bash
gcloud run services update-traffic SERVICE --to-revisions LIST
```

<br />

- Replace <var translate="no">SERVICE</var> with the name of the service.
- Replace <var translate="no">LIST</var> with a comma delimited list of revisions and percentages:  
  <var translate="no">REVISION1</var>=<var translate="no">PERCENTAGE1</var>,<var translate="no">REVISION2</var>=<var translate="no">PERCENTAGE2</var>,<var translate="no">REVISIONn</var>=<var translate="no">PERCENTAGEx</var>  
  for example, `hello2-00005-red=25,hello2-00001-bod=25,hello2-00002-nan=50`.

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Below the `spec` attribute, locate
   and update the `traffic` attribute so that the new revision serves only a
   small amount of traffic:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION-A
           percent: PERCENT-A
         - revisionName: REVISION-B
           percent: PERCENT-B
         - revisionName: REVISION-C
           percent: PERCENT-C

   Note that percentages must add up to 100. Replace
   - <var translate="no">REVISION-A</var>, <var translate="no">REVISION-B</var>, <var translate="no">REVISION-C</var> with the revisions you are allotting traffic to.
   - <var translate="no">PERCENT-A</var>, <var translate="no">PERCENT-B</var>, <var translate="no">PERCENT-C</var> with the percentage for the corresponding revision.
3. Replace the service with its new configuration using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```
4. Wait for the update to complete: you should see a message that the
   new revision you are gradually rolling out has been deployed and is serving
   `5` percent (or whatever gradual value you used) of traffic.

### Terraform

Add the following to your Terraform file:

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {
        containers {
          image = "us-docker.pkg.dev/cloudrun/container/hello"
        }
        revision = "green"
      }

      # Define the traffic split for each revision
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#traffic
      traffic {
        percent  = 25
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }

      traffic {
        percent = 75
        # This revision needs to already exist
        revision = "blue"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }
    }

Apply the changes by entering `terraform apply`.

## Send all traffic to the latest revision

When you deploy a new revision, you can make this revision and all future ones
serve 100% of the traffic as soon as possible, overriding any established
traffic split:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Locate the service in the services list, and click it.

3. Configure your service, then click **View diff and redeploy**.

4. Make sure the checkbox labeled **Serve this revision immediately** is
   selected. This will override any existing traffic splitting, with the new
   revision serving 100 percent of traffic.

5. Click **Deploy changes**.

### gcloud

To send all traffic to the most recently deployed revision:

<br />

```bash
gcloud run services update-traffic SERVICE --to-latest
```

<br />

Replace <var translate="no">SERVICE</var> with the name of the service.

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Below the `spec` attribute, locate
   and update the `traffic` attribute to the following

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - latestRevision: true
           percent: 100

3. Replace the service with its new configuration using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```
4. Wait for the update to complete: you should see a message that the
   (latest) revision is deployed and is serving `100` percent of traffic.

### Terraform

Add the following to your Terraform file:

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {}

      traffic {
        percent = 100
        type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
      }
    }

Apply the changes by entering `terraform apply`.

## Use tags for testing, traffic migration and rollbacks

> [!IMPORTANT]
> **Important:** If you have minimum instances configured at the [service-level](https://docs.cloud.google.com/run/docs/configuring/min-instances#setting-service-level), traffic tags do not allocate minimum instances for tagged revisions. If you have minimum instances configured at the [revision-level](https://docs.cloud.google.com/run/docs/configuring/min-instances#setting), traffic tags allocate minimum instances for tagged revisions.

To avoid incurring billing costs for tagged revisions, use [service-level
minimum instances](https://docs.cloud.google.com/run/docs/configuring/min-instances#setting-service-level) or
[remove tags](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration#remove-tags) on revisions when you don't need them anymore.

A common use case for this feature is to use it for testing and vetting of a
new service revision before it serves any traffic, in this typical sequence:

1. Run integration tests on a container during development.
2. Deploy the container to a Google Cloud project that you use only for staging, serving no traffic, and test against a tagged revision.
3. Deploy it to production, without serving traffic, and test against a tagged revision in production.
4. Migrate traffic to the tagged revision.

> [!NOTE]
> **Note:** You can [delete a revision](https://docs.cloud.google.com/run/docs/managing/revisions#delete) that is not serving traffic (0% allocation), even if it has an assigned tag. When a revision is deleted, Cloud Run automatically attempts to remove the associated tag from the service's traffic configuration. If you encounter errors when updating your service traffic, it might indicate that a tag in your traffic configuration is still referencing a deleted revision. See [Troubleshooting](https://docs.cloud.google.com/run/docs/troubleshooting#revision-del) for details.

### Deploy a new tagged revision

To deploy a new revision of an existing service to production:

### gcloud

> [!NOTE]
> **Note:** If you are using the gcloud CLI to deploying from source, make sure to have the [required roles](https://docs.cloud.google.com/run/docs/deploying-source-code#required_roles) granted to you and to use `--source` instead of `--image`, and add `--function` if deploying a function.

```bash
gcloud run deploy myservice --image IMAGE_URL  --no-traffic --tag TAG_NAME
```

Replace:

- <var translate="no">IMAGE_URL</var> with the URL for your image.
- <var translate="no">TAG_NAME</var> with your lowercase tag name.

The tag lets you directly test the new revision at a specific URL, without
serving traffic. The URL starts with the tag name you provided: for example
if you used the tag name `green` on the service `myservice`, you would
test the tagged revision at the URL `https://green---myservice-abcdef.a.run.app`

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Below the `traffic` attribute, locate and update the `tag` attribute
   that corresponds to the revision that you want to add a tag to:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION
           percent: 100
         - revisionName: REVISION-A
           tag: TAG-A
         - revisionName: REVISION-B
           tag: TAG-B
         - revisionName: REVISION-C
           tag: TAG-C

   Replace:
   - <var translate="no">TAG-A</var>, <var translate="no">TAG-B</var>, <var translate="no">TAG-C</var> with the tag associated to each revision.
   - <var translate="no">REVISION</var> with the name of an existing revision that you want to send all of the traffic to.
3. Create or update the service using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```

   The `gcloud run services replace` command defaults to using `service.yaml` file if present.

### Terraform

Add the following to your Terraform file and gradually update the traffic percentage from old revision to the newest revision with the new [tag](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#tag).
Keep in mind that every traffic change will require another `terraform apply` to be executed.

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          # image or tag must be different from previous revision
          image = "us-docker.pkg.dev/cloudrun/container/hello"
        }
        revision = "blue"
      }

      # Define the traffic split for each revision
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#traffic
      traffic {
        percent = 100
        # This revision needs to already exist
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }

      traffic {
        # Deploy new revision with 0% traffic
        percent  = 0
        revision = "blue"
        tag      = "tag-name"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }
    }

Apply the changes by entering `terraform apply`.

### Remove a tag

To remove a tag from a revision:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Select a service in the services list.

3. Navigate to the **Revision history** tab.

4. Click the **Manage revision tags** icon next to the tag you want to delete.

5. Click the **Delete** icon to remove the current tag used in your revision.

6. Click **Save**.

### gcloud

To remove a revision tag:

```bash
gcloud run services update-traffic SERVICE --remove-tags TAG_NAME
```

Replace

- <var translate="no">TAG_NAME</var> with the name of the tag you are migrating traffic to
- <var translate="no">SERVICE</var> with the name of the service you are removing the tag from

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Make any desired configuration changes to the service.

3. Below the `spec` attribute, locate
   and remove the `tag` attribute for the tagged revision:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION
           tag: TAG_NAME
           percent: PERCENT-NEW

4. Replace the service with its new configuration using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```

### Terraform

Add the following to your Terraform file:

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {}

      # Define the traffic split for each revision
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#traffic
      traffic {
        percent = 100
        # This revision needs to already exist
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }

      traffic {
        # No tags for this revision
        # Keep revision at 0% traffic
        percent = 0
        # This revision needs to already exist
        revision = "blue"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }
    }

Apply the changes by entering `terraform apply`.

> [!NOTE]
> **Note:** If the revision doesn't exist, you will receive the error: `Error creating Service: googleapi: Error 400: spec.template.spec: Revision template was empty`.

### Migrating traffic to a tagged revision

After confirming that the new revision works properly, you can start migrating
traffic to it using the Google Cloud console, the Google Cloud CLI
command line, Terraform, or a YAML file:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Locate the service in the services list, and click it.

3. Select the tagged revision you want to send traffic to.

4. Click **Manage traffic**.

5. Click **Send all traffic to one revision** if you want the revision to
   receive 100% of the traffic or **Split traffic across multiple revisions**
   to distribute traffic across multiple revisions.

6. Select the revisions from the menu and specify the traffic
   percentage, if applicable.

7. Click **Save**. You don't need to redeploy to change the traffic
   percentages.

### gcloud

To migrate traffic to a specific revision tag:

```bash
gcloud run services update-traffic myservice --to-tags TAG_NAME=TRAFFIC_PERCENT
```

Replace

- <var translate="no">TAG_NAME</var> with the name of the tag you are migrating traffic to
- <var translate="no">TRAFFIC_PERCENT</var> with the percentage of traffic you want to the tagged revision to serve, for example, `1`.

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Make any chosen configuration changes to the service.

3. Below the `spec` attribute, locate
   and update the `traffic` attribute for the tagged revision so that the tagged
   revision serves only a small amount of traffic:

       apiVersion: serving.knative.dev/v1
       kind: Service
       metadata:
        name: SERVICE
       spec:
       ...
         traffic:
         - revisionName: REVISION
           tag: TAG_NAME
           percent: PERCENT-NEW
         - revisionName: REVISION-FORMER
           percent: PERCENT-FORMER

   Note that the percentages must add up to 100. Replace
   - <var translate="no">REVISION</var> with the name of the tagged revision.
   - <var translate="no">TAG_NAME</var> with the name of the tag you are rolling out gradually.
   - <var translate="no">PERCENT-NEW</var> with the traffic percentage you want to send to the tagged revision, for example use `10` to send 10% of the traffic to that revision.
   - <var translate="no">REVISION-FORMER</var> with the name of the currently serving revision.
   - <var translate="no">PERCENT-FORMER</var> with the traffic percentage you want to send to the old revision
4. Replace the service with its new configuration using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```
5. Wait for the update to complete: you should see a message that the
   new revision you are gradually rolling out has been deployed and is serving
   the traffic percentage value you used.

### Terraform

Add the following to your `.tf` file:

    resource "google_cloud_run_v2_service" "default" {
      name     = "my-service"
      location = "us-central1"

      deletion_protection = false # set to true to prevent destruction of the resource

      template {}

      # Define the traffic split for each revision
      # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#traffic
      traffic {
        # Update revision to 50% traffic
        percent = 50
        # This revision needs to already exist
        revision = "green"
        type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
      }

      traffic {
        # Update tag to 50% traffic
        percent = 50
        # This tag needs to already exist
        tag = "tag-name"
      }
    }

Over a period of hours or days, as needed, gradually update from one tag to the other, increasing the percentage as needed for the tagged revision.

Apply by entering `terraform apply` after every change.

> [!NOTE]
> **Note:** If the revision doesn't exist, you will receive the error: `Error creating Service: googleapi: Error 400: spec.template.spec: Revision template was empty`.

## What's next

- Learn about [using Cloud Deploy to set up a continuous-delivery pipeline to deploy to Cloud Run](https://docs.cloud.google.com/build/docs/deploying-builds/deploy-cloud-run).