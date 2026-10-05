This page describes how to troubleshoot errors you might encounter while using Cloud Run. [Personalized Service Health](https://docs.cloud.google.com/service-health/docs/overview) publishes
all Cloud Run incidents that stem from the
underlying Google Cloud infrastructure to identify Google Cloud service disruptions
impacting your projects. You should also consider [setting up alerts on Personalized Service Health events](https://docs.cloud.google.com/service-health/docs/configure-alerts-dashboard). For information
about incidents affecting all Google Cloud services, see the [Google Cloud Service Health](https://status.cloud.google.com/summary) dashboard.

Check for existing issues or open new issues in the
[public issue trackers](https://docs.cloud.google.com/support/docs/issue-trackers).

For other errors messages not listed In this page, see [Known issues in Cloud Run](https://docs.cloud.google.com/run/docs/known-issues). If you continue to encounter errors even after following
the steps in this guide, [contact support](https://cloud.google.com/support-hub).

See the following sections for guidance on how to resolve issues in Cloud Run:

- [Deployment errors](https://docs.cloud.google.com/run/docs/troubleshooting#deployment)
- [Serving errors](https://docs.cloud.google.com/run/docs/troubleshooting#serving)
- [Connectivity and security errors](https://docs.cloud.google.com/run/docs/troubleshooting#connectivity)

> [!NOTE]
> **Note:** You can get AI-powered help from Gemini Cloud Assist chat to troubleshoot Cloud Run errors. For more information, see [Troubleshoot Cloud Run apps with Gemini assistance](https://docs.cloud.google.com/run/docs/troubleshooting/overview#troubleshoot-with-gemini).

## Deployment errors

This section describes the common deployment errors in Cloud Run and
methods to troubleshoot them.

### Container failed to start

The following error occurs when you try to deploy:

```
Container failed to start. Failed to start and then listen on the port defined by the PORT environment variable.
```

To resolve this issue, follow these steps:

1. Verify that you can
   [run your container image locally](https://docs.cloud.google.com/run/docs/testing/local). If your
   container image cannot run locally, you need to diagnose and fix the issue
   locally first.

2. Check if your container is
   [listening for requests on the on the correct port](https://docs.cloud.google.com/run/docs/container-contract#port).
   Your container must listen for incoming requests on the port that is defined
   by Cloud Run and provided in the `PORT` environment variable. For
   instructions on how to specify the port,see
   [Configuring containers for services](https://docs.cloud.google.com/run/docs/configuring/services/containers)

3. Check if your container is listening on all
   network interfaces, commonly denoted as `0.0.0.0`. Notably, your container
   should *not* listen on `127.0.0.1`.

4. Verify that your container image is compiled
   for 64-bit Linux as required by the
   [container runtime contract](https://docs.cloud.google.com/run/docs/container-contract#languages).

   > [!NOTE]
   > **Note:** If you build your container image on a ARM based machine, then it might not work as expected when used with Cloud Run. To solve this issue, [build your image using Cloud Build](https://docs.cloud.google.com/run/docs/building/containers#builder).

5. Use Cloud Logging to
   [look for application errors in `stdout` or `stderr` logs](https://docs.cloud.google.com/run/docs/logging).
   You can also
   [look for crashes captured in Error Reporting](https://docs.cloud.google.com/run/docs/error-reporting).

   You might need to update your code or your revision settings to fix errors
   or crashes. You can also
   [troubleshoot your service locally](https://docs.cloud.google.com/run/docs/tutorials/local-troubleshooting).

### Container import error

The following error occurs when you try to deploy:

```
The service has encountered an error during container import. Please try again later. Resource readiness deadline exceeded.
```

To resolve this issue, follow these steps:

1. Ensure container's file system does not contain
   non-utf8 characters.

2. Some Windows based Docker images make use of
   [foreign layers](https://docs.microsoft.com/en-us/virtualization/windowscontainers/about/faq#how-do-i-make-my-container-images-available-on-air-gapped-machines-).
   Cloud Run's control plane doesn't support foreign-layers. To
   resolve this issue, try setting the `--allow-nondistributable-artifacts` flag
   in the Docker daemon.

### The feature is not supported

The following error occurs when you call the Cloud Run Admin API:

```
The feature is not supported in the declared launch stage
```

This error occurs when you call the Cloud Run Admin API directly and use a beta
feature without specifying a launch stage annotation or field.

To resolve this issue, add the launch stage field to the requests.

Refer to the following examples for adding launch stage references when using
the v1 or the v2 REST API:

- Launch stage annotation to a client request using
  [JSON and the v1 REST API](https://docs.cloud.google.com/run/docs/reference/rest/v1/namespaces.services#Service):

  ```json
    "annotations": {
      "run.googleapis.com/launch-stage": "BETA"
    }
  ```
- [LaunchStage](https://docs.cloud.google.com/run/docs/reference/rest/v2/LaunchStage) reference to a
  client request using [JSON and the v2 REST API](https://docs.cloud.google.com/run/docs/reference/rest/v2/projects.locations.services#Service):

  ```json
  "launchStage": "BETA"
  ```
- Launch stage annotation to a service request using
  [YAML and the v1 REST API](https://docs.cloud.google.com/run/docs/reference/rest/v1/namespaces.services#Service):

  ```yaml
  kind: Service
  metadata:
  annotations:
    run.googleapis.com/launch-stage: BETA
  ```

### User `root` is not found

The following error occurs when the customer managed encryption keys are
specified using a `--key` parameter:

```
ERROR: "User \"root\""not found in /etc/passwd
```

To resolve this issue, specify `USER 0` instead of `USER root` in the
Dockerfile.

### Default Compute Engine service account is deleted

The following error occurs during deployment:

```
ERROR: (gcloud.run.deploy) User EMAIL_ADDRESS does not have permission to access namespace NAMESPACE_NAME (or it may not exist): Permission 'iam.serviceaccounts.actAs' denied on service account PROJECT_NUMBER-compute@developer.gserviceaccount.com (or it may not exist).
```

This issue occurs in either of the following scenarios:

- The
  [default **Compute Engine** service account](https://docs.cloud.google.com/run/docs/configuring/services/service-identity)
  doesn't exist in the project, and a service account isn't specified with the
  `--service-account` flag at the time of deployment.

- The developer or principal deploying the service is doesn't have the
  [required permissions](https://docs.cloud.google.com/run/docs/deploying#permissions_required_to_deploy)
  for the default **Compute Engine** service account to deploy.

To resolve this issue:

1. Specify a service account using the `--service-account` flag:

       gcloud run services update SERVICE_NAME --service-account SERVICE_ACCOUNT

2. Verify that the service account you specify has the
   [permissions required to deploy](https://docs.cloud.google.com/run/docs/deploying#permissions_required_to_deploy).

To verify if the default Compute Engine service agent exists in your Google Cloud project, follow these steps:

1. In the Google Cloud console, go to the Identity and Access Management **Permissions** page:

   [Go to Permissions](https://console.cloud.google.com/iam-admin/iam)
2. Select the **Include Google-provided role grants** checkbox.

3. In the **Principals** list, locate the ID of the Compute Engine service
   agent, which follows the format, `PROJECT_NUMBER-compute@developer.gserviceaccount.com`.

### Issues with Cloud Build service account

The following error occurs during source deployments when the Cloud Build
service account doesn't have the required permissions or is disabled:

```
ERROR: (gcloud.run.deploy) NOT_FOUND: Build failed. The service has encountered an internal error. Please try again later. This command is authenticated as EMAIL_ADDRESS which is the active account specified by the [core/account] property.
```

Cloud Build changed the default behavior for how Cloud Build uses
service accounts in new projects. This is detailed in
[Cloud Build default service account change](https://docs.cloud.google.com/build/docs/cloud-build-service-account-updates). As a result of this change, new projects
deploying to Cloud Run from source code for the first time might be
using a default Cloud Build service account with insufficient permissions for
deploying from source.

To resolve this issue, follow these steps:

- Review the Cloud Build guidance on changes to the default service account and
  [opt out](https://docs.cloud.google.com/build/docs/cloud-build-service-account-updates#what_do_you_need_to_do)
  of these changes.

- Grant the [Cloud Run Builder](https://docs.cloud.google.com/run/docs/reference/iam/roles#run.builder)
  (`roles/run.builder`) role to the build service account.

### Cloud Run Service Agent missing permission to read the image

The following error occurs when you try to deploy from a project
using an image that is stored in the Artifact Registry, using the `gcr.io` domain
in a different project:

```
Google Cloud Run Service Agent must have permission to read the image, gcr.io/PROJECT-ID/IMAGE-NAME. Ensure that the provided container image URL is correct and that above account has permission to access the image. If you just enabled the Cloud Run API, the permissions might take a few minutes to propagate. Note that PROJECT-ID/IMAGE-NAME is not in project PROJECT-ID-2. Permission must be granted to the Google Cloud Run Service Agent from this project.
```

You might also see the following error when you try to deploy from a project
using an image that is stored in the Artifact Registry in a different project:

```
ERROR: (gcloud.run.deploy) PERMISSION_DENIED: User must have permission to read
the image, REGION.pkg.dev/PROJECT_ID/ARTIFACT_REGISTRY_REPO/IMAGE:latest. Ensure that the provided container image URL is correct
and that the above account has permission to access the image. If you just enabled
the Cloud Run API, the permissions might take a few minutes to propagate. Note
that the image is from project PROJECT_ID, which is not the same as
this project PROJECT_ID.
```

To resolve this issue, follow these troubleshooting recommendations:

- Follow the instructions for
  [deploying container images from other Google Cloud projects](https://docs.cloud.google.com/run/docs/deploying#other-projects)
  to ensure that your principals have the necessary permissions.

- This issue might also occur if the project is in a VPC Service Controls
  perimeter with a restriction on the Cloud Storage API that prohibits
  requests from the Cloud Run service agent. To fix this:

  1. Open Logs Explorer in the Google Cloud console. (Do not use the
     **Logs** page inside the Cloud Run page):

     [Go to Logs Explorer](https://console.cloud.google.com/logs/query)
  2. Enter the following text in the query field:

         protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"
         severity=ERROR
         protoPayload.status.details.violations.type="VPC_SERVICE_CONTROLS"
         protoPayload.authenticationInfo.principalEmail="service-PROJECT_NUMBER@serverless-robot-prod.iam.gserviceaccount.com"

  3. If you see any log entries after you use this query, examine the log
     entries to determine whether you need to update your VPC Service Controls policies.
     They may indicate that you need to add
     `service-PROJECT_NUMBER@serverless-robot-prod.iam.gserviceaccount.com`
     to a pre-existing access policy.

### Missing permissions for source deployments

The following errors might occur when deploying from the source:

    ERROR: (gcloud.run.deploy) EMAIL_ADDRESS does not have permission
    to access namespaces instance PROJECT_ID (or it may not exist): Google
    Cloud Run Service Agent does not have permission to get access tokens for
    the service account SERVICE_ACCOUNT. Please give SERVICE_ACCOUNT
    permission iam.serviceAccounts.getAccessToken on the service account.

    Alternatively, if the service account is unspecified or in the same project you
    are deploying in, ensure that the Service Agent is assigned the Google
    Cloud Run Service Agent role roles/run.serviceAgent. This
    command is authenticated as EMAIL_ADDRESS, which is the active account
    specified by the [core/account] property.

Every Cloud Run service is associated with a service account that
serves as its [identity](https://docs.cloud.google.com/run/docs/configuring/services/service-identity) when
the service accesses other resources. This service account
might be the default service account (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`) or a user-managed service account.

In environments where multiple services are accessing different resources, you
might use per-service identities with different user-managed service accounts instead of
the default service account.

To resolve this issue, grant the deployer account the [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) role (`roles/iam.serviceAccountUser`)
on the service account that is used as the service identity.
This predefined role contains the `iam.serviceAccounts.actAs` permission, which
is required to attach a service account on the service or revision. A user who
creates a user-managed service account is automatically granted the `iam.serviceAccounts.actAs` permission, however, other deployers must have this
permission granted by the user who creates the user-managed service account.

For more information regarding access requirements for any new service accounts
you create, see [Get recommendations to create dedicated service accounts](https://docs.cloud.google.com/run/docs/configuring/services/service-identity#getting-recommendations).

### User has insufficient permissions to complete source deployments

The following error occurs when the deployer account is missing the required
permissions on your project:

    ERROR: (gcloud.run.deploy) 403 Could not upload file EMAIL_ADDRESS does
    not have storage.objects.create access to the Google Cloud Storage object. Permission storage.objects.create denied on resource (or it may not exist). This
    command is authenticated as EMAIL_ADDRESS which is the active account.

To resolve this error, ask your administrator to grant you the following Identity and Access Management roles:

- [Cloud Run Source Developer](https://docs.cloud.google.com/iam/docs/roles-permissions/run#run.sourceDeveloper) (`roles/run.sourceDeveloper`) on your project.
- [Service Usage Consumer](https://docs.cloud.google.com/iam/docs/roles-permissions/serviceusage#serviceusage.serviceUsageConsumer) (`roles/serviceusage.serviceUsageConsumer`) on your project.
- [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) (`roles/iam.serviceAccountUser`) on the Cloud Run service identity. For more information, see [Deployment permissions](https://docs.cloud.google.com/run/docs/reference/iam/roles#additional-configuration).

### Error when deploying a Cloud Run service from other Google Cloud projects

The following error occurs when you deploy a Cloud Run service from
a source project to a target project:

    Failed to create service.
    Operation failed due to missing permissions.

    Google Cloud Run Service Agent does not have permission to get access
    tokens for the service account SERVICE_ACCOUNT. Please give
    SERVICE_ACCOUNT permission iam.serviceAccounts.getAccessToken
    on the service account. Alternatively, if the service account is unspecified or
    in the same project you are deploying in, ensure that the Service Agent is
    assigned the Google Cloud Run Service Agent role roles/run.serviceAgent.

To resolve this issue, follow these steps:

1. Grant the [Service Account User](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountUser) (`roles/iam.serviceAccountUser`) role on the service account that you use as the service identity in your target project.

2. Grant the [Service Account Token Creator](https://docs.cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountTokenCreator) (`roles/iam.serviceAccountTokenCreator`) role to the Cloud Run service account in the target project. Add the Cloud Run [service agent](https://docs.cloud.google.com/iam/docs/service-agents) email (`service-PROJECT_NUMBER@SERVICE_DOMAIN.iam.gserviceaccount.com`) as the principal from the source project.

3. Turn off the `iam.disableCrossProjectServiceAccountUsage` organization policy.

For detailed instructions, see [Configure service identity for services](https://docs.cloud.google.com/run/docs/configuring/services/service-identity#use_service_accounts_in_other_projects).

### Errors when deploying your Python source code to Cloud Run

When you deploy a Cloud Run service from source code with the Python
runtime, one of the following errors occurs:

-

  ```
  Revision REVISION_NAME is not ready and cannot serve traffic.
  The user provided container failed to start and listen on port defined by PORT=8080
  environment variable within the allocated timeout. This can happen if the port is
  misconfigured or if the timeout is too short. The healthcheck timeout can be extended.
  ```
- Deployment succeeds with HTTP 500 error codes in the logs.

The Python buildpack sets the default entrypoint for [Cloud Run source deployments](https://docs.cloud.google.com/run/docs/deploying-source-code). For Python version 3.13
and later, the Python buildpack sets the entrypoint based on the web service configuration in your `requirements.txt` file. If you don't specify a
web server or framework in the `requirements.txt` file, or use Python version 3.12 and earlier, the Python buildpack sets the default entrypoint to `gunicorn -b :8080 main:app`. For more information, see [Building a Python application](https://docs.cloud.google.com/docs/buildpacks/python#run-source-deploys).

You can resolve this issue in several ways. For example, you can specify one of the following web servers in your `requirements.txt` file:

- `gunicorn`:

        # https://pypi.org/project/gunicorn/
        gunicorn==21.2.0

- `fastapi` and `uvicorn`:


      # https://pypi.org/project/fastapi
      fastapi[standard]==0.116.1

      # https://pypi.org/project/uvicorn
      uvicorn==0.35.0

Alternatively, you can follow either of these steps to resolve deployment errors:

- Specify the entrypoint by running the following source deploy command:

      gcloud run deploy SERVICE --source .  --set-build-env-vars GOOGLE_ENTRYPOINT="ENTRYPOINT"

  Replace the following:
  - <var translate="no">SERVICE</var>: the name of the service you want to deploy to.
  - <var translate="no">ENTRYPOINT</var>: the default entrypoint you want to use for your source code.
- Use a [Procfile](https://docs.cloud.google.com/run/docs/tips/python#other_wsgi_servers) to set an
  entrypoint.

## Serving errors

This section lists issues that you might encounter with serving and provides
suggestions for how to fix each of them.

### Revision does not exist or is deleted

The following issue occurs when updating your service traffic:

```
Revision REVISION_NAME does not exist or is deleted
```

If you encounter errors when updating your service traffic (such as "Revision
does not exist or is deleted"), it might indicate that a tag in your traffic
configuration is still referencing a deleted revision. To resolve this, you must
manually update your traffic allocation to remove the orphaned tag:

- **Using the CLI:** Run `gcloud run services update-traffic <var>SERVICE_NAME</var> --to-latest` or explicitly reassign the traffic tags to an existing, active revision.
- **Using the Google Cloud console:** Navigate to your service, go to the **Revisions** tab, and edit the traffic allocation to remove the tag pointing to the deleted revision.

### HTTP 404: Not Found

The following issue occurs during serving:

```
`HTTP 404`:Not found
```

You might encounter `HTTP 404` errors in the following scenarios:

1. An incorrect request URL or application code returns `404` errors. To resolve
   this issue, follow these steps:

   1. Check if the URL you requested is correct. You can verify the URL either in
      the service details page in the Google Cloud console or by running the following command:

          gcloud run services describe SERVICE_NAME | grep URL

   2. Inspect where your app returns `404` error codes. If your
      app returns `404`, you can find it in Cloud Logging. Also, verify that
      the app does not return a `404` error code when you
      [run it locally](https://docs.cloud.google.com/run/docs/testing/local).

   3. Make sure that your app doesn't start listening on its configured port before it
      is ready to receive requests.

2. The request doesn't reach the container, leading to a `404` error in the following
   scenarios:

   - A request doesn't satisfy the specified network restriction, especially
     when Cloud Run service's [ingress settings](https://docs.cloud.google.com/run/docs/securing/ingress#settings)
     are set to **Internal** or **Internal and Cloud Load Balancing**.

   - The Cloud Run service's [default `run.app` URL is disabled](https://docs.cloud.google.com/run/docs/securing/ingress#disable-url), and a client attempts to reach the
     service at that `run.app` URL.

   In both of these scenarios, you can't find the `404` error in
   Cloud Logging, even when you apply the following filter:

       resource.type="cloud_run_revision"
       log_name="projects/PROJECT_ID/logs/run.googleapis.com%2Frequests"
       httpRequest.status=404

3. With the same ingress settings, the request might be blocked by
   VPC Service Controls based on the [caller's context, including project and IP address](https://docs.cloud.google.com/vpc-service-controls/docs/overview). To check for a VPC Service Controls
   policy violation:

   1. Open Logs Explorer in the Google Cloud console:

      [Go to Logs Explorer](https://console.cloud.google.com/logs/query)
   2. Enter the following text in the query field:

          resource.type="audited_resource"
          log_name="projects/PROJECT_ID/logs/cloudaudit.googleapis.com%2Fpolicy"
          resource.labels.method="run.googleapis.com/HttpIngress"

   3. If you see any log entries after you use this query, examine the log
      entries to determine whether or not you need to update your VPC Service Controls
      policies.

4. Access your service endpoint with a load balancer using the Python runtime.
   To resolve this issue, [verify the URL mask for your load balancer](https://docs.cloud.google.com/load-balancing/docs/https/setting-up-https-serverless#constructing-url-mask), and ensure that the
   URL path you specify for the load balancer matches the path in your Python source code.

### No available container instances

The following error occurs during serving:

```
HTTP 429
The request was aborted because there was no available instance.
The Cloud Run service might have reached its maximum container instance
limit or the service was otherwise not able to scale to incoming requests.
This might be caused by a sudden increase in traffic, a long container startup time or a long request processing time.
```

To resolve this issue, check the [**Container instance count**](https://docs.cloud.google.com/run/docs/monitoring#view-metrics) metric for your
service and consider increasing this limit if your usage is nearing the maximum.
For more information, see [Set maximum instances for services](https://docs.cloud.google.com/run/docs/configuring/max-instances), and if you need more instances, [request a quota increase](https://docs.cloud.google.com/run/quotas#increase).

### Cloud Run couldn't manage the rate of traffic

The following error occurs either during serving or when the service
hasn't reached its [maximum container instance limit](https://docs.cloud.google.com/run/docs/configuring/max-instances):

```
HTTP 500
The request was aborted because there was no available instance
```

To resolve this issue, follow these steps:

1. Address the following possible root causes:

   - A huge sudden increase in traffic.
   - A long [cold start time](https://docs.cloud.google.com/run/docs/tips#start_containers_quickly).
   - A long request processing time, or a sudden increase in request processing time.
   - The service reaching its maximum container instance limit (`HTTP 429`).
   - Transient factors attributed to the Cloud Run service.
2. Implement exponential backoff and retries for requests that the client must
   not drop. A short and sudden increase in traffic or request
   processing time might only be visible in Cloud Monitoring if you zoom
   in to a 10-second resolution.

3. When the root cause of the issue is a period of heightened transient errors
   attributable solely to Cloud Run, contact [support](https://docs.cloud.google.com/run/docs/getting-support).

### Cloud Run instance fails to start

The following error occurs during serving:

```
HTTP 500
The request failed because the instance could not start successfully.
```

This error occurs when the container fails to start and become healthy within
your configured time. While this can have multiple causes, a common reason is
the container's inability to access a required secret from
Secret Manager.

To resolve this issue, consider the following:

1. Verify IAM permissions: Ensure that your Cloud Run
   service account has the [Secret Manager Secret Accessor](https://docs.cloud.google.com/iam/docs/roles-permissions#secretmanager.secretAccessor) (`roles/secretmanager.secretAccessor`) role on the secret
   you are trying to access.

2. Check the secret path: Verify that you [specify the correct secret name and
   version](https://docs.cloud.google.com/run/docs/configuring/services/secrets#access-secrets) in your
   application's configuration.

3. Inspect network configuration: If you are using a VPC Service Controls perimeter
   or firewall rules, ensure that you [allow egress
   traffic](https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc) to
   `secretmanager.googleapis.com`.

4. Output effective logs: Add [logging](https://docs.cloud.google.com/run/docs/logging#container-logs) to your
   application's startup process, especially around fetching secrets, to
   diagnose specific failures.

### Operation is not implemented

The following error occurs when you specify an incorrect <var translate="no">REGION</var> while
invoking your Cloud Run job, such as when you deploy a job in the
region `asia-southeast1`, and invoke your job using `southeast1-asia` or
`asia-southeast`:

```
HTTP 501
Operation is not implemented, or supported, or enabled.
```

For the list of supported regions, see [Cloud Run locations](https://docs.cloud.google.com/run/docs/locations).

### Service returning `5xx` errors and Cloud Run jobs and worker pools failing to start

> [!WARNING]
>
> **Preview
> --- Budget spend caps**
>
>
> This feature is
>
> subject to the "Pre-GA Offerings Terms" in the General Service Terms section of the
> [Service Specific
> Terms](https://docs.cloud.google.com/terms/service-terms#1).
>
> Pre-GA features are available "as is" and might have limited support.
>
> For more information, see the
> [launch stage descriptions](https://cloud.google.com/products/#product-launch-stages).

If your Google Cloud billing account reaches a spend cap, your
Cloud Run resources might return HTTP `5xx` status codes.

Additionally, if you run Cloud Run jobs or worker pools, new task
executions or worker pool instances might fail to start.

To resolve this issue:

1. Check the [Cloud Run console](https://console.cloud.google.com/run/). If your account reached a spend cap, you'll see an alert banner.
2. Go to the [Cloud Billing console](https://console.cloud.google.com/billing) to view your budgets and alerts.
3. To resume operation, lift or adjust the spend cap limit.

After you lift the spend cap, it might take up to 30 minutes for the
Cloud Run resource to resume serving
traffic. For more information, see
[Known issues](https://docs.cloud.google.com/run/docs/known-issues#spend-cap-recovery).

### Default credentials not found

The following error occurs when your application isn't authenticated properly
due to missing files, invalid credential paths, or incorrect environment variables
assignments:

```
HTTP 503: System.InvalidOperationException System.InvalidOperationException your Default
credentials were not found.
```

To resolve this issue:

1. [Install and initialize the gcloud CLI](https://docs.cloud.google.com/sdk/docs/install).

2. Set up Application Default Credentials (ADC) with the credentials that are
   associated with the user. Configure ADC using:

         gcloud auth application-default login

   A sign-in screen appears. After you sign in, your credentials are stored in
   the [local credential file](https://docs.cloud.google.com/docs/authentication/application-default-credentials#personal),
   used by ADC.
3. Use the `GOOGLE_APPLICATION_CREDENTIALS` environment variable to provide the
   location of a credential JSON file within your Google Cloud project.

   For more information, see [Set up Application Default Credentials](https://docs.cloud.google.com/docs/authentication/provide-credentials-adc).

### Container instances exceed memory limits

The following `HTTP 500` or `HTTP 503` error occurs during serving in Cloud Logging:

```
While handling this request, the container instance was found to be using too much memory and was terminated. This is likely to cause a new container instance to be used for the next request to this revision. If you see this message frequently, you may have a memory leak in your code or may need more memory. Consider creating a new revision with more memory.
```

To resolve this issue:

1. Determine if your container instances are exceeding the available memory. Look for related errors in the `varlog/system` logs.
2. If the instances are exceeding the available memory, consider [increasing the memory limit](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits).

In Cloud Run, files written to the local file system count
towards the available memory. This also includes any log files that are written
to locations other than `/var/log/*` and `/dev/log`.

### Unable to process some requests due to high concurrency setting

The following error occurs when your container instances are using a high
CPU load to process requests, and as a result, are unable to process all of
the requests:

```
HTTP 503
The Cloud Run service probably has reached its maximum container instance limit. Consider increasing this limit.
```

To resolve this issue, follow these steps:

1. [Increase the maximum number of container instances](https://docs.cloud.google.com/run/docs/configuring/max-instances)
   for your service.

2. Lower the service's [concurrency](https://docs.cloud.google.com/run/docs/about-concurrency). For more
   information, see [Set maximum concurrent requests per instance](https://docs.cloud.google.com/run/docs/configuring/concurrency).

### Cloud Logging errors related to container restrictions

When running under root namespaces that violate constraints listed in the [container runtime contract](https://docs.cloud.google.com/run/docs/container-contract),
you might see Cloud Logging logs that contain errors from the Linux kernel
such as "Operation not permitted" or "Permission denied." These errors appear
when the system calls attempting to perform these actions are rejected. For
guidance on making your containers more compatible with Cloud Run
execution environments, see [Adapt your containers for Cloud Run](https://docs.cloud.google.com/run/docs/deploying#adapt-containers).

Attempts to mount file systems might have logs such as the following:

- `mount.nfs: Operation not permitted`
- `mount.cifs: Operation not permitted`

If your application tries to modify files under `/proc` or `/sys` with tools
like `sysctl`, your logs might contain errors such as the following:

- `sysctl: permission denied on key "vm.max_map_count"`

Attempts to run `sudo` will fail with logs that declare the following:

- `sudo: The "no new privileges" flag is set`

Other system calls, like `mlockall`, might fail with errors such as the
following:

- `msg="mlockall syscall failed" error="cannot allocate memory"`

Errors are unique to the code in question and to how well you implement logging
and error handling.

### Cloud Logging errors related to pending queue request aborts

One of the following errors occur when Cloud Run fails to scale
up fast enough to manage traffic:

-

      The request was aborted because there was no available instance:
      severity=WARNING ( Response code: 429 ) Cloud Run cannot
      scale due to the `max-instances` limit you set
      during configuration.

-

      severity=ERROR ( Response code: 500 ) Cloud Run intrinsically
      cannot manage the rate of traffic.

To resolve this issue, follow these steps:

1. Address the root causes that might cause scaling failures, such as:

   - A huge sudden increase in traffic.
   - Long [cold start](https://docs.cloud.google.com/run/docs/about-instance-autoscaling#idle-instance) time.
   - Long request processing time.
   - High source code error rate.
   - Reaching the [maximum instance limit](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits#exceed_scaling_ability) and preventing the system from scaling.
   - Transient factors attributed to the Cloud Run service.

   For more information on resolving scaling issues, and optimizing performance, see
   [General development tips](https://docs.cloud.google.com/run/docs/tips/general).
2. For HTTP trigger-based services or functions, have the client implement exponential
   backoff and retries for requests that must not be dropped. If you are triggering
   services from Workflows, you can use the [`try/retry` syntax](https://docs.cloud.google.com/workflows/docs/reference/syntax/retrying) to achieve this.

3. For background or event-driven services or functions, Cloud Run supports
   [at-least-once delivery](https://docs.cloud.google.com/run/docs/tips/function-retries#semantics_of_retry).
   Even without explicitly enabling retry, Cloud Run automatically
   re-delivers the event and retries the execution. See
   [Retrying event-driven functions](https://docs.cloud.google.com/run/docs/tips/function-retries)
   for more information.

4. For issues pertaining to cold starts, configure
   [minimum instances](https://docs.cloud.google.com/run/docs/tips/general#use_minimum_instances_to_reduce_cold_starts) to reduce the amount of cold starts with a higher billing implication.

5. When the root cause of the issue is a period of heightened transient errors
   attributed solely to Cloud Run or if you need assistance with
   your issue, [contact support](https://cloud.google.com/support-hub).

### Identity token signature redacted by Google

The following error occurs during development and testing phases:

```
SIGNATURE_REMOVED_BY_GOOGLE
```

This error might occur in the following scenarios:

- The user logs in by using Google Cloud CLI or Cloud Shell.

- The user generates an ID token by using `gcloud` commands.

- The user tries to use the ID token to invoke a non-public Cloud Run
  service.

This is the expected default behavior. Google removes the token signature due
to security concerns to prevent any non-public Cloud Run service from
replaying ID tokens that are generated in this manner.

To resolve this issue, invoke your private service with a new ID token. For more
information, see [Test your private service](https://docs.cloud.google.com/run/docs/authenticating/developers#testing).

### OpenBLAS warning in logs

If you use [OpenBLAS](https://www.openblas.net/)-based
libraries such as NumPy with the
[first generation execution environment](https://docs.cloud.google.com/run/docs/about-execution-environments),
you might see the following warning in your logs:

```
OpenBLAS WARNING - could not determine the L2 cache size on this system,
assuming 256k`
```

The OpenBLAS warning occurs when the container sandbox used by the first generation
execution environment doesn't expose low level hardware features. This warning
doesn't impact your service. To avoid OpenBLAS warnings log entries,
[switch to the second generation execution environment](https://docs.cloud.google.com/run/docs/configuring/execution-environments#setting).

### Spark fails when obtaining IP address of machine to bind to

When Spark fails while obtaining the IP address of the binding machine, one of
the following errors occurs:

```
assertion failed: Expected hostname (not IP) but got <IPv6 ADDRESS>
```

```
assertion failed: Expected hostname or IPv6 IP enclosed in [] but got <IPv6 ADDRESS>
```

To resolve this issue, set the [`SPARK_LOCAL_IP`](https://spark.apache.org/docs/latest/configuration.html#environment-variables) environment variable to `127.0.0.1` in
your Dockerfile, for example, `ENV SPARK_LOCAL_IP="127.0.0.1"`. If you don't
set the `SPARK_LOCAL_IP` environment variable, it defaults to its IPv6 counterpart
instead of the localhost. Additionally, Spark doesn't recognize the environment
variable set as `RUN export SPARK_LOCAL_IP="127.0.0.1"`.

### Cannot access files using NFS

| Error | Suggested remedy |
|---|---|
| `mount.nfs: Protocol not supported` | Some base images, such as `debian` and [`adoptopenjdk/openjdk11`](https://hub.docker.com/r/adoptopenjdk/openjdk11), are missing the [nfs-kernel-server](https://github.com/kubernetes-sigs/blob-csi-driver/issues/220) dependency. |
| `mount.nfs: Connection timed out` | If the connection times out, make sure you are providing the correct IP address of the filestore instance. |
| `mount.nfs: access denied by server while mounting IP_ADDRESS:/FILESHARE` | If access was denied by the server, make sure the file share name is correct. |

> [!NOTE]
> **Note:** To include all the logs from the mount process, use the `--verbose` flag in combination with the `mount` command:   
> `mount --verbose -o nolock $IP_ADDRESS:/$FILESHARE_NAME $MNT_DIR`.

### Cannot access files using Cloud Storage FUSE

See the Cloud Storage FUSE [troubleshooting guide](https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/overview).

### High latency when CPU utilization is low

Your service might experience high request latencies or fail to scale up under
load, even though Cloud Monitoring shows average CPU utilization is well
below the typical 60% scaling target.

#### Potential cause:

This might occur if your application is single-threaded for CPU-bound
tasks but is deployed on an instance with multiple vCPUs. Your application
might max out one vCPU core while other cores remain mostly idle. The Cloud Run
autoscaler uses the average CPU utilization across all vCPUs; this average might
be low in these cases, which prevents CPU-based scaling.

#### Solutions:

- For single-threaded applications:
  - Prefer configuring your service with 1 vCPU if its memory requirements can be met (see [Memory limits and CPU minimums](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits#cpu-minimum)). This helps CPU utilization metrics accurately reflect load.
  - If multiple vCPUs are necessary due to high memory needs that exceed 1-vCPU limits, CPU-based autoscaling will likely be less effective. In this scenario, lower the max concurrency setting to encourage scaling sooner based on request throughput. See [Concurrency Configuration](https://docs.cloud.google.com/run/docs/configuring/concurrency).
- For multi-vCPU configurations: Ensure your application is architected to effectively utilize all allocated vCPUs (for example, using multiple worker processes or threads).

## Connectivity and security errors

This section describes the common connectivity and security errors in
Cloud Run and methods to troubleshoot them.

### Client is not authenticated properly

The following error occurs during serving:

```
HTTP 401: The request was not authorized to invoke this service
```

To resolve this issue:

1. If a [service account invokes](https://docs.cloud.google.com/run/docs/authenticating/service-to-service#set_up_the_service_account) your Cloud Run service, set
   the audience claim (`aud`) of the Google-signed ID token to the following:

   - If you set the `aud` to the URL of the receiving service using the format
     `https://SERVICE.run.app` or `https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION`, your service must
     [require authentication](https://docs.cloud.google.com/run/docs/securing/managing-access). Invoke your Cloud Run service using the Cloud Run URL or through a
     load balancer URL. For examples on sending authenticated requests, see
     [Invoke with an HTTPS request](https://docs.cloud.google.com/run/docs/triggering/https-request#testing-private).

   - If you set the `aud` to the Client ID of an OAuth 2.0 Client ID with type
     **Web application** , using the format `nnn-xyz.apps.googleusercontent.com`,
     you can invoke your Cloud Run service through an [HTTPS load balancer secured by IAP](https://docs.cloud.google.com/iap/docs/enabling-cloud-run). We recommend
     this approach for an Application Load Balancer backed by multiple [Cloud Run services in different regions](https://docs.cloud.google.com/iap/docs/authentication-howto#obtaining_an_oidc_token_for_the_default_service_account).

   - If you set the `aud` to a configured [custom audience](https://docs.cloud.google.com/run/docs/configuring/custom-audiences), use the exact values provided. For example,
     if the custom audience is `https://service.example.com`,
     the audience claim value must also be `https://service.example.com`.

2. Make sure that your requests include an `Authorization: Bearer ID_TOKEN`
   header, or an `X-Serverless-Authorization: Bearer ID_TOKEN` header for custom authorization, and that the token is an ID token, not an access or refresh
   token. A `401` error might occur in the following scenarios due to incorrect
   authorization format:

   - The [authorization token](https://docs.cloud.google.com/run/docs/authenticating/service-to-service#acquire-token)
     uses an invalid format.

   - The authorization header isn't a [JSON Web Token (JWT)](https://en.wikipedia.org/wiki/JSON_Web_Token) with a valid signature.

   - The authorization header contains multiple JWTs.

   - Multiple authorization headers are present in the request.

   To check claims on a JWT, use the [jwt.io](https://jwt.io/) tool.
3. If you get invalid tokens when using the
   [metadata server to fetch ID and access tokens](https://docs.cloud.google.com/run/docs/securing/service-identity#generate-access-token) to authenticate requests with the Cloud Run service or job identity with an HTTP proxy to route
   egress traffic, add the following hosts to the [HTTP proxy exceptions](https://docs.cloud.google.com/run/docs/troubleshooting#http-proxy-exceptions):

   - `169.254.*` or `169.254.0.0/16`

   - `*.google.internal`

4. A `401` error commonly occurs when [Cloud Client Libraries](https://docs.cloud.google.com/apis/docs/cloud-client-libraries)
   use the metadata server to fetch [Application Default Credentials](https://docs.cloud.google.com/docs/authentication/set-up-adc-attached-service-account) to authenticate REST or gRPC invocations.
   If you don't define the HTTP proxy exceptions, the following behavior results:

   - If different Google Cloud workloads host a Cloud Run service or job and the HTTP proxy, even if the Cloud Client Libraries
     fetch the credentials, the service account that's assigned to the HTTP proxy workload generates the tokens. The tokens might not
     have the required permissions to perform the intended [Google Cloud API](https://cloud.google.com/apis)
     operations. This is because the service account fetches the tokens from the view of the
     HTTP proxy workload's metadata server, instead of the Cloud Run service or job.

   - If the HTTP proxy isn't hosted in Google Cloud, and you route metadata server
     requests using the proxy, then the token requests fail and
     the [Google Cloud APIs](https://docs.cloud.google.com/apis) operations don't authenticate.

5. Redeploy your service to [allow public access](https://docs.cloud.google.com/run/docs/authenticating/public) if this is supported by your organization. This is useful for testing.

### Client is not authorized to invoke the service

One of the following errors occur while invoking your service:

```
HTTP 403: The request was not authenticated. Either allow public access or set the proper Authorization header
```

```
HTTP 403: Forbidden: Your client does not have permission to get URL from this server.
```

A `403` error might occur when the IAM
member used to generate the authorization token is missing the `run.routes.invoke`
permission. Grant this permission to the user generating the token.

Additionally, if there is an entry for the error with the format `resource.type = "cloud_run_revision"` in Cloud Logging, follow these steps to resolve the error:

1. To make your service invocable by anyone,
   [update the IAM settings](https://docs.cloud.google.com/run/docs/securing/managing-access#making_a_service_public), and make the service public.

2. To make your service invocable only by certain identities,
   [invoke your service with the proper authorization token](https://docs.cloud.google.com/run/docs/authenticating/overview):

   - If a [developer](https://docs.cloud.google.com/run/docs/authenticating/developers#before_you_start) or
     an end [user](https://docs.cloud.google.com/run/docs/authenticating/end-users#troubleshooting) invokes your service, grant the `run.routes.invoke` permission. You can provide this
     permission through the Cloud Run Admin (`roles/run.admin`) and Cloud Run Invoker (`roles/run.invoker`) roles.

   - If a [service account](https://docs.cloud.google.com/run/docs/authenticating/service-to-service#set_up_the_service_account) invokes your service,
     ensure that the service account is a member of the Cloud Run
     service, and grant the Cloud Run Invoker (`roles/run.invoker`)
     role.

   - Calls missing an auth token might cause the `403` error. If calls with
     a valid auth token still lead to the `403` error, grant the IAM
     member that generates the token the `run.routes.invoke` permission.

When you encounter a `403` error and don't find the log entry `resource.type = "cloud_run_revision"`, it might be due to
VPC Service Controls blocking a Cloud Run service that has [ingress settings](https://docs.cloud.google.com/run/docs/securing/ingress#settings) configured to `All`. For more information on
troubleshooting VPC Service Controls denials, see [404 errors](https://docs.cloud.google.com/run/docs/troubleshooting#404).

### Error when accessing the service from a web browser

The following issue occurs when you access a Cloud Run service from a web
browser:

    403 Forbidden
    Your client does not have permission to get URL from this server.

When you invoke a Cloud Run service from a web browser, the browser
sends a `GET` request to the service. However, the
request doesn't contain the authorization token of the calling user. To resolve
this issue, follow these steps:

1. Use [Identity-Aware Proxy (IAP)](https://docs.cloud.google.com/iap/docs/concepts-overview)
   with Cloud Run. IAP lets you establish a
   central authorization layer for applications accessed over HTTPS. With
   IAP, you can use an application-level access control model
   instead of network-level firewalls. For more details on configuring
   Cloud Run with IAP, see [Enabling Identity-Aware Proxy for Cloud Run](https://docs.cloud.google.com/iap/docs/enabling-cloud-run).

2. As a temporary workaround, access your service through a web browser using the
   Cloud Run proxy in Google Cloud CLI. To proxy a service
   locally, run the following command:

       gcloud run services proxy SERVICE --project PROJECT-ID

   Cloud Run proxies the private service
   to `http://localhost:8080` (or to the port you specify with `--port`), providing
   the token of the active account or another token you specify.
   This is the recommended way to test privately a website or API in your browser.
   For more information, see [Testing private services](https://docs.cloud.google.com/run/docs/authenticating/developers#testing).
3. [Allow public access](https://docs.cloud.google.com/run/docs/authenticating/public) to your
   service. This is helpful for testing, or when your service is a
   public API or website.

### Connection reset by peer

One of the following errors occurs when a peer across the network unexpectedly closes
the TCP connection established by the application:

```
Connection reset by peer
```

```
asyncpg.exceptions.ConnectionDoesNotExistError: connection was closed in the middle of operation
```

```
grpc.StatusRuntimeException: UNAVAILABLE: io exception
```

```
psycopg.OperationalError: the connection is closed
```

```
ECONNRESET
```

To resolve this issue, follow these steps:

- If you are trying to perform background work with CPU throttling, use
  the [instance-based billing](https://docs.cloud.google.com/run/docs/configuring/billing-settings#setting)
  setting.

- Ensure that you are within the
  [outbound requests timeouts](https://docs.cloud.google.com/run/docs/container-contract#outbound-timeout).
  If your application maintains any connection in an idle state beyond this
  threshold, the gateway needs to reap the connection.

- By default, the TCP socket option `keepalive` is disabled for
  Cloud Run. There is no direct way to configure the
  `keepalive` option at the service level.
  To enable the `keepalive` option for each socket connection,
  provide the required socket options when opening a new TCP socket connection,
  depending on the client library you are using for this connection in
  your application.

- Occasionally, [outbound connections are reset](https://docs.cloud.google.com/run/docs/container-contract#outbound-reset)
  due to infrastructure updates. If your application reuses long-lived
  connections, we recommend that you configure your application to
  re-establish connections to avoid the reuse of a dead connection.

- If you're using an HTTP proxy to route your Cloud Run services or
  jobs egress traffic, and the proxy enforces maximum connection duration,
  the proxy might silently drop long-running TCP connections such as the ones
  established using connection pooling. This causes HTTP clients to fail when
  reusing an already closed connection.
  If you intend to route egress traffic through an HTTP proxy, you must implement
  connection validation, retries, and exponential backoff. For connection pools, configure maximum values for connection age, idle connections, and connection idle timeout.

### Connection timeouts

The following errors occur when an application attempts to create a new TCP
connection with a remote host, and the connection takes too long to
establish:

```
java.io.IOException: Connection timed out
```

```
ConnectionError: HTTPSConnectionPool
```

```
dial tcp REMOTE_HOST:REMOTE_PORT: i/o timeout / context error
```

```
Error: 4 DEADLINE_EXCEEDED: Deadline exceeded
```

To resolve connection timeout issues, follow these steps:

1. If you're routing all egress traffic through a VPC network,
   either using [VPC connectors](https://docs.cloud.google.com/run/docs/configuring/vpc-connectors)
   or [Direct VPC egress](https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc), follow these steps:

   - Define all the necessary firewall rules to allow ingress
     traffic for the [VPC connectors](https://docs.cloud.google.com/run/docs/configuring/vpc-connectors#restrict-access).

   - VPC firewall rules must [allow ingress](https://docs.cloud.google.com/run/docs/configuring/vpc-connectors#allow-ranges)
     traffic from the VPC connectors or the Direct VPC egress
     subnet to reach the destination host or subnet.

   - Be sure that you have all the required routes to allow correct traffic routing to the
     destination hosts and back. This is important when routing egress
     traffic through [VPC Network Peering](https://docs.cloud.google.com/vpc/docs/vpc-peering) or
     [hybrid cloud connectivity](https://cloud.google.com/hybrid-connectivity), as packets traverse
     multiple networks before reaching the remote host.

2. If you're using an HTTP proxy to route all egress traffic from your
   Cloud Run services or jobs, the remote hosts must be
   reachable using the proxy.

   Traffic routed through an HTTP proxy might be delayed depending on the
   proxy's resource utilization. If you are routing HTTP egress traffic using
   a proxy, implement retries, exponential backoff, or circuit breakers.

### Configure HTTP proxy exceptions

When using an HTTP proxy to route your Cloud Run services or jobs
egress traffic, add exceptions for [Cloud APIs](https://docs.cloud.google.com/apis),
and other non-proxied hosts and subnets, to prevent latency,
connection timeouts, connection resets and authentication errors.

Non-proxied hosts and subnets must include, at minimum, the following:

- `127.0.0.1`
- `169.254.*` or `169.254.0.0/16`
- `localhost`
- `*.google.internal`
- `*.googleapis.com`

Optionally, non-proxied hosts might include:

- `*.appspot.com`
- `*.run.app`
- `*.cloudfunctions.net`
- `*.gateway.dev`
- `*.googleusercontent.com`
- `*.pkg.dev`
- `*.gcr.io`

To set HTTP proxy exceptions for egress networking, configure the following:

- Environment variables: `NO_PROXY` or `no_proxy`.

  - Standard Python HTTP libraries, such as `urllib` and `requests`, don't support asterisk wildcards `*` in the `NO_PROXY` or `no_proxy` environment variables. To match subdomains, use a leading dot instead of `*`, for example, `.googleapis.com` or `.google.internal`.
- Java Virtual Machine flag [`http.nonProxyHosts`](https://docs.oracle.com/en/java/javase/23/docs/api/java.base/java/net/doc-files/net-properties.html):

  - The system property `https.nonProxyHosts` isn't defined. This
    system property applies to both HTTP and HTTPS.

  - The system property `http.nonProxyHosts` doesn't support
    CIDR notation. You must use pattern matching expressions.

### Malformed response or container instance connection issue

The following error occurs when there is a container instance connection issue:

```
HTTP 503
The request failed because either the HTTP response was malformed or connection to the instance had an error.
```

To resolve this issue, follow these steps:

1. Check [Cloud Logging](https://docs.cloud.google.com/run/docs/logging)
   for the following errors:

   - Out of memory errors. If the logs contain error messages regarding container
     instances exceeding memory limits, see the recommendations in the
     [Container instances are exceeding memory limits](https://docs.cloud.google.com/run/docs/troubleshooting#memory)
     section.

   - [Liveness probe](https://docs.cloud.google.com/run/docs/configuring/healthchecks#liveness-probes) failures
     with the following error in the logs:

     ```
     LIVENESS HTTP probe failed 1 time consecutively for container CONTAINER_NAME on port 8080. The instance has been shut down.
     ```

     When your instance fails to respond successfully to the probe within the
     timeout period, follow these steps:
     - Enable instrument logging and [tracing](https://docs.cloud.google.com/run/docs/trace) to determine the cause of the increased latency.

     - [Increase the timeout period](https://docs.cloud.google.com/run/docs/configuring/healthchecks#configure-probes)
       for the liveness probe.

2. If requests are terminating with error code `503`
   before reaching the
   [request timeout set in Cloud Run](https://docs.cloud.google.com/run/docs/configuring/request-timeout),
   update the request timeout setting for your language framework:

   - Node.js developers must update the
     [`server.timeout` property through `server.setTimeout`](https://nodejs.org/api/http.html#http_server_settimeout_msecs_callback)
     (use `server.setTimeout(0)` to achieve an unlimited timeout) depending
     on the version you are using.

   - Python developers need to update
     [Gunicorn's default timeout](https://docs.gunicorn.org/en/latest/settings.html#timeout) (`[CRITICAL] WORKER TIMEOUT`).

3. In some scenarios, a `503` error code might occur due to a downstream network
   bottleneck, such as during load testing. For
   example, if your service routes traffic through a
   Serverless VPC Access connector, ensure that the connector
   doesn't exceed its throughput threshold by following these steps:

   1. Open Serverless VPC Access in the Google Cloud console:

      [Go to Serverless VPC Access](https://console.cloud.google.com/networking/connectors/list)
   2. Check for any **red** bars in the throughput
      chart histogram. If there is a **red** bar
      consider increasing the max instances or instance type your connector
      uses. Alternatively, compress traffic sent through a
      Serverless VPC Access connector.

4. If a container instance receives more than
   800 requests per second, the available TCP sockets might be exhausted. To resolve this, [turn on HTTP/2](https://docs.cloud.google.com/run/docs/configuring/http2) for your service, and make the required changes to your service to
   support HTTP/2.

### Gateway timeout error

The following error occurs when your
service doesn't return a response within a specified time, and the request ends:

```
HTTP 504
The request has been terminated because it has reached the maximum request timeout.
```

For more information about this error, see the [Container runtime contract](https://docs.cloud.google.com/run/docs/container-contract#responses).

To troubleshoot this issue, follow these steps:

- If your service is processing long requests,
  [increase the request timeout](https://docs.cloud.google.com/run/docs/configuring/request-timeout).

- Instrument logging and [tracing](https://docs.cloud.google.com/run/docs/trace) to understand where your
  app is spending time before exceeding your configured request timeout.

- [Outbound connections are reset](https://docs.cloud.google.com/run/docs/container-contract#outbound-reset)
  occasionally, due to infrastructure updates. If your application reuses long-lived
  connections, we recommend that you configure your application to
  re-establish connections to avoid the reuse of a dead connection.

  Depending on your app's logic or error handling, a `504` error might be a signal
  that your application is trying to reuse a dead connection and the
  request blocks until your configured request timeout. Use a [liveness probe](https://docs.cloud.google.com/run/docs/configuring/healthchecks#liveness-probes) to terminate an instance that
  returns persistent errors.
- Out of memory errors that happen inside the app's code,
  for example, `java.lang.OutOfMemoryError`, don't necessarily terminate a
  container instance.
  If memory usage doesn't exceed the
  [container memory limit](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits), then Cloud Run won't terminate the instance. Depending on how the app
  handles app-level out of memory errors, requests might not go through until
  they exceed your configured request timeout.

  To terminate the container instance, follow these steps:
  - Configure your app-level memory limit to be greater than your
    container memory limit.

  - Use a liveness probe to help terminate an instance that returns persistent
    errors.

### Custom domain stuck while provisioning certificate


One of the following errors occurs when you map a custom domain:

```
The domain is available over HTTP.  Waiting for certificate provisioning. You must configure your DNS records for certificate issuance to begin and to accept HTTP traffic.
```

```
Waiting for certificate provisioning. You must configure your DNS records for certificate issuance to begin.
```

To resolve this issue:

1. Wait at least 24 hours. Provisioning the SSL certificate usually takes about
   15 minutes, but it can take up to 24 hours.

2. Verify that you've properly updated your DNS records at your domain
   registrar using the [Google Admin Toolbox dig tool](https://toolbox.googleapps.com/apps/dig/). The DNS records in your domain registrar must match what the
   Google Cloud console [prompts you to add](https://docs.cloud.google.com/run/docs/mapping-custom-domains#dns_update).

3. Verify the **root** of the domain under your account using
   one of the following methods:

   - Follow the instructions for
     [adding verified domain owners](https://docs.cloud.google.com/run/docs/mapping-custom-domains#adding_verified_domain_owners_to_other_users_or_service_accounts), and check that your account is listed as a **Verified Owner**.

   - Use the
     [Search console](https://search.google.com/search-console/welcome).

   > [!NOTE]
   > **Note:** For example, if you want to map `subdomain.example.com` or `subdomain1.subdomain2.example.com`, you must verify ownership of `example.com`.

4. Verify that the certificate for the domain is not expired. To find the
   expiry bounds, use the following command:

       echo | openssl s_client -servername 'ROOT_DOMAIN' -connect 'ROOT_DOMAIN:443' 2>/dev/null | openssl x509 -startdate -enddate -noout

### Client disconnect does not propagate to Cloud Run

When you use HTTP/1.1 on Cloud Run, client disconnect events are not
propagated to the Cloud Run container.

To resolve this issue, use Websockets or HTTP/2.0, which propagate client disconnects.