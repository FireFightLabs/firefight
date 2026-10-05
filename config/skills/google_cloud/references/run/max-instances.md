This page describes how to set the maximum number of instances that
can be used for your Cloud Run service using
the default [Cloud Run autoscaling](https://docs.cloud.google.com/run/docs/about-instance-autoscaling)
behavior. To manually scale your service, see [Manual scaling](https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling).

Specifying maximum instances in
Cloud Run lets you limit the scaling of your service in response
to incoming requests, although this maximum setting can be exceeded
for a brief period due to circumstances such as [traffic spikes](https://docs.cloud.google.com/run/docs/about-instance-autoscaling#spikes).

You can use this setting as a way to control your costs or to
limit the number of connections to a backing service, such as to a database.

For information about the maximum instance limits that might apply to your
service, refer to [Maximum instances limits](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits).

For more information on the way Cloud Run autoscales container
instances, refer to [Instance autoscaling](https://docs.cloud.google.com/run/docs/about-instance-autoscaling).

## Apply maximum instances at service-level versus revision-level

You can configure maximum instances at the [service](https://docs.cloud.google.com/run/docs/resource-model#services)
level or at the [revision](https://docs.cloud.google.com/run/docs/resource-model#revisions) level.
Google recommends that you use service-level maximum instances to cap the number
of instances of a service unless you have a specific need to limit instances at
the revision level.
By default, Cloud Run sets 100 instances for each revision.
To allow your service to scale to more instances, modify this value.

When applying maximum instances, the settings go into effect as follows:

- Service-level: immediately
- Revision-level: upon deployment of the revision

### Tagged revisions and service-level maximum instances

[Tagged revisions](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration#tags) are
started, but only count toward the service-level maximum instances if they are a
part of a traffic split.

## Required roles


To get the permissions that
you need to configure and deploy Cloud Run services,

ask your administrator to grant you the
following IAM roles:

- [Cloud Run Developer](https://docs.cloud.google.com/iam/docs/roles-permissions/run#run.developer) (`roles/run.developer`) on the Cloud Run service
- [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) (`roles/iam.serviceAccountUser`) on the service identity


If you are deploying a [service](https://docs.cloud.google.com/run/docs/deploying-source-code#required_roles)
or [function](https://docs.cloud.google.com/run/docs/deploy-functions#required-roles) from source code, you
must also have additional roles granted to you on your project and
Cloud Build service account.

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

## Cost considerations

The maximum instances setting lets you establish a cost-safety limit to manage
cost. Setting a higher maximum number prioritizes availability, but it introduces
potential billing risks from unexpected traffic spikes or misconfigurations. As
a cost safeguard, configure this setting at the service level when you initially deploy
your service. We suggest starting with a maximum
instances value of 3 to protect your budget from unexpected spikes.

Review [Cloud Run pricing](https://cloud.google.com/run/pricing) or
estimate costs with the [pricing calculator](https://cloud.google.com/products/calculator)
for more information. For additional cost control tools, see [resource allocation quotas](https://docs.cloud.google.com/run/quotas#cloud_run_limits)
or [billing budgets and alerts](https://docs.cloud.google.com/billing/docs/how-to/budgets).

## Configure service-level maximum instances

You can change the maximum instances setting using the Google Cloud console,
the Google Cloud CLI, YAML, or Terraform when you
[create a new service](https://docs.cloud.google.com/run/docs/deploying#service) or
[deploy a new revision](https://docs.cloud.google.com/run/docs/deploying#revision).

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. If you are configuring a new service, click **Deploy container** to
   display the **Create service** form. Locate the **Service scaling** form.

3. If you are configuring an existing service, click the service to display
   its detail panel, then the **Scaling** tab.

4. Under the **Service scaling** , find the field labelled **Maximum number
   of instances** and specify the required maximum number of container
   instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits)
   possible for your service. To remove the service-level limit, delete the
   value you set. This reverts the setting to its default.

5. Click **Create** for a new service. Click **View diff \& redeploy** , then **Deploy changes** for an existing service.

### gcloud

You can [update the maximum number of instances](https://docs.cloud.google.com/sdk/gcloud/reference/run/services/update)
of a given service by using the following command:

```bash
gcloud run services update SERVICE --max MAX-VALUE
```

Replace the following:

- <var translate="no">SERVICE</var>: the name of your service.
- <var translate="no">MAX-VALUE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits) possible for your service. To remove the service-level limit, delete the value you set. This reverts the setting to its default.

You can also set the maximum number of instances during
[deployment](https://docs.cloud.google.com/sdk/gcloud/reference/run/deploy) using the following command:

```bash
gcloud run deploy --image IMAGE_URL --max MAX-VALUE
```

Replace the following:

- `IMAGE_URL`: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the [repository](https://docs.cloud.google.com/artifact-registry/docs/repositories/create-repos#docker) <var translate="no">REPO_NAME</var> must already be created. The URL follows the format of `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG` .
- <var translate="no">MAX-VALUE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits).

### YAML


Any configuration change leads to the
creation of a new revision. Subsequent revisions will also automatically get
this configuration setting unless you make explicit updates to change it.

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Update the `run.googleapis.com/maxScale:` attribute:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
     annotations:
       run.googleapis.com/maxScale: 'MAX-INSTANCE'
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service
   - <var translate="no">MAX-INSTANCE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits) possible for your service. To remove the service-level limit, delete the value you set. This reverts the setting to its default.
3. Create or update the service using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```

   The `gcloud run services replace` command defaults to using `service.yaml` file if present.

### Terraform

To learn how to apply or remove a Terraform configuration, see
[Basic Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands).
Add the following to a [`google_cloud_run_v2_service`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) resource in your Terraform configuration:  

    resource "google_cloud_run_v2_service" "default" {
    name     = "SERVICE"
    location = "REGION"

    scaling {
      max_instance_count = MAX_INSTANCE
    }

    template {
      containers {
        image = "IMAGE_URL"
      }
    }
    }

Replace the following:

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">REGION</var>: the Google Cloud region---for example, `europe-west1`.
- <var translate="no">MAX_INSTANCE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits).
- `IMAGE_URL`: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the [repository](https://docs.cloud.google.com/artifact-registry/docs/repositories/create-repos#docker) <var translate="no">REPO_NAME</var> must already be created. The URL follows the format of `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`

## View service-level maximum instances

To view the current service-level maximum instances settings for your
Cloud Run service:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Click that service to open its **Service details** panel.

3. Click the **Scaling** tab to view the current setting.

### gcloud

1. Use the following command:

   ```bash
   gcloud run services describe SERVICE
   ```
2. Locate the value for **Scaling: Auto (Min: <var translate="no">MIN_VALUE</var>, Max: <var translate="no">MAX_VALUE</var>)** in the returned configuration.

## Configure revision-level maximum instances

Any configuration change leads to the
creation of a new revision. Subsequent revisions will also automatically get
this configuration setting unless you make explicit updates to change it.

By default, Cloud Run revisions are configured to scale up to a maximum
of 100 instances.

Revision-level scaling is only available for services that previously had the
feature configured.

### Console

1. In the Google Cloud console, go to Cloud Run:

   [Go to Cloud Run](https://console.cloud.google.com/run)
2. Select **Services** from the Cloud Run navigation menu, and click
   **Deploy container** to configure a new service.
   If you are configuring an existing service, click the service.

3. If you are configuring a new service, fill out the initial service
   settings page, then click **Containers, Networking, Security** to expand the
   service configuration page.

4. If you are configuring an existing service, click the **Scaling** tab.

5. In the **Revision scaling** section, specify the maximum number of container
   instances in the **Maximum number of instances** field.

6. Click **Create** for a new service. Click **View diff \& redeploy** , then **Deploy changes** for an existing service.

### gcloud

You can [update the maximum number of instances](https://docs.cloud.google.com/sdk/gcloud/reference/run/services/update)
of a given service by using the following command:

```bash
gcloud run services update SERVICE --max-instances MAX-VALUE
```

Replace the following:

- <var translate="no">SERVICE</var>: the name of your service.
- <var translate="no">MAX-VALUE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits).

### YAML

1. If you are creating a new service, skip this step.
   If you are updating an existing service, download its [YAML configuration](https://docs.cloud.google.com/run/docs/reference/yaml/v1):

   ```bash
   gcloud run services describe SERVICE --format export > service.yaml
   ```
2. Update the `autoscaling.knative.dev/maxScale:` attribute:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
         annotations:
           autoscaling.knative.dev/maxScale: 'MAX-INSTANCE'
         name: REVISION
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service
   - <var translate="no">MAX-INSTANCE</var>: the required maximum number of container instances, using any integer value from `1` to the [maximum limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits).
   - `REVISION`: a new revision name or delete it (if present). If you supply a new revision name, it **must** meet the following criteria:
     - Starts with `SERVICE-`
     - Contains only lowercase letters, numbers and `-`
     - Does not end with a `-`
     - Does not exceed 63 characters
3. Create or update the service using the following command:

   ```bash
   gcloud run services replace service.yaml
   ```

   The `gcloud run services replace` command defaults to using `service.yaml` file if present.

## View revision-level maximum instance settings

Revision-level scaling is only available for services that previously had the
feature configured.

To view the current revision-level maximum instances settings for your
Cloud Run service:

### Console

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Click that service to open its **Service details** panel.

3. Click the **Scaling** tab.

4. Under **Revision scaling** , view the **Maximum number of instances**.

### gcloud

1. Use the following command:

   ```bash
   gcloud run services describe SERVICE
   ```
2. Locate the value for **Max instances:** in the returned configuration.

### Use both service-level and revision-level minimum or maximum instances

The following table shows the behavior if you combine service-level maximum
instances with revision-level minimum or maximum instances:

| Service-level setting | Revision-level setting | Behavior |
|---|---|---|
| Service-level maximum instances set | Revision-level maximum instances set | Effective maximum instance limit is the lesser value between revision-level maximum instances and service-level maximum instances. |
| Service-level maximum instances set | Revision-level minimum instances set | If service-level maximum instances is set to a value lower than revision-level minimum instances, then the revision starts instances up to the service-level maximum instances, and won't reach the configured revision-level minimum instances. |

### Use service-level maximum instances with traffic splitting

If you use [traffic splitting](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration#split-traffic),
the service-level maximum instances are distributed across the revisions based on the
proportion of the traffic split. For example, if the service-level maximum
instances = 100, a 50/50 traffic split allocates 50 service-level maximum instances
to each revision.
The following table shows a sample configuration scenario:

| Sample configuration | Resulting behavior |
|---|---|
| Service-level maximum instances set (scenario where there are no revision-level settings): 100 - Traffic spit for Revision A: 10% - Traffic split for Revision B: 10% - Traffic split for Revision C : 80% | A portion of the service-level maximum instances is allocated to each revision. The effective maximum instances for each revision is fixed based on traffic split. Maximum instances for Revision A is 10, Revision B is 10, and Revision C is 80. > [!NOTE] > **Note:** When using traffic splitting, revisions might reach their effective maximum instances limit, and return [`No available container instances`](https://docs.cloud.google.com/run/docs/troubleshooting#429-max-instances) error, even if the service as a whole, hasn't reached the service-level maximum instances limit. |