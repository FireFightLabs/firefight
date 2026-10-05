[Video](https://www.youtube.com/watch?v=Cj2Tb-CoM4c)

Cloud Run health checks ensure that your container instances are running
correctly and are able to serve traffic. With Cloud Run health checks,
you can customize when your container is ready to receive requests, and
when your container should be considered unhealthy to require a restart.

## Use cases

You can configure the following types of health check probes:

- [Startup probes](https://docs.cloud.google.com/run/docs/configuring/healthchecks#startup-probes) determine whether the container has
  started and is ready to accept traffic.

  - When you configure a startup probe, liveness and readiness checks are disabled until the startup probe determines that the container is started, to prevent interference with the service startup.
  - Startup probes are especially useful if you use liveness checks on slow starting containers, because startup probes prevents the containers from being shut down prematurely before the containers are up and running.
- [Liveness probes](https://docs.cloud.google.com/run/docs/configuring/healthchecks#liveness-probes) determine whether to restart a
  container.

  - Restarting a container in this case can increase service availability in the event of bugs.
  - Liveness probes are intended to restart individual instances that can't be recovered in any other way. They should be used primarily for unrecoverable instance failures, such as catching a deadlock where a service is running, but is unable to make progress. You can require a liveness probe for every container by using [custom organization
    policies](https://docs.cloud.google.com/run/docs/securing/custom-constraints#require-liveness-probe).
  - When a service experiences repeated probe failures, Cloud Run limits instance restarts to prevent uncontrolled crash loops.
- [Readiness probes](https://docs.cloud.google.com/run/docs/configuring/healthchecks#readiness-probes)

  Readiness probes determine when an instance in your Cloud Run
  service should serve traffic. The readiness checks begin after the
  container's startup probe successfully passes. If an instance fails its
  readiness probe beyond the failure threshold value you configure,
  Cloud Run stops sending new traffic to it. Cloud Run
  doesn't terminate the instance and sends traffic back to
  the instance when it starts passing its readiness probe again.

Your container is required to implement the startup, liveness, and readiness
probes consistently. Once the startup check passes, Cloud Run considers
your container ready to serve traffic.

We recommend that you encapsulate your logic so the startup probe accounts
for readiness. Since Cloud Run can route traffic to a new instance
before the first readiness probe completes, make sure that passing the startup
probe also ensures readiness to safely serve traffic immediately. When the
startup probe succeeds, we treat the container as ready to receive traffic.

## Configure startup probes

Any configuration change leads to the
creation of a new revision. Subsequent revisions will also automatically get
this configuration setting unless you make explicit updates to change it.

You can configure HTTP, TCP, and gRPC probes using Google Cloud console, YAML, or
Terraform:

### Console

1. In the Google Cloud console, go to Cloud Run:

   [Go to Cloud Run](https://console.cloud.google.com/run)
2. Select **Services** from the Cloud Run navigation menu.

3. If you are configuring a new service, click **Deploy container** ,
   fill out the initial service settings page, then click **Containers, Networking, Security**
   to expand the service configuration page.

4. If you are configuring an existing service, click the service, then click
   the **Containers** tab.

5. In the **Health checks** section, click **Add health check** to open the
   **Add health check** configuration panel.

6. From the **Select health check type** menu, select **Startup check**.

7. From the **Select probe type** menu, select the type of the probe you want
   to use, for example, HTTP or gRPC. This displays the probe configuration form.
   Probe configuration varies by probe type. Configure the probe settings:

   - If you are using HTTP probes:

     - Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your service code to respond to the probe. The endpoint name (for example, `/startup`, `/health` or `/are_you_ready`) must match the `path` in the probe configuration. HTTP health check endpoints are externally accessible and follow the same principles as any other externally exposed HTTP service endpoints.
     - Use the **Path** field to specify the relative path to the endpoint, for example, `/`.
     - Select the **HTTP Headers** checkbox to specify optional custom headers. Specify the header name in the **Name** field and header value in the **Value** field. Click **Add HTTP header** to specify more headers.
   - If you are using gRPC probes:

     - Ensure that your container image implements the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
   - For **Port** , specify the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port)
     used for your service.

   - For **Initial delay**, specify the number of seconds to wait after the
     container has started before performing the first probe. Specify a value
     from 0 seconds to 600 seconds (1800 for GPU).
     The default value is 0 seconds.

   - For **Period** , specify the period (in seconds) at which to perform the
     probe. For example `2` to perform the probe every 2 seconds. Specify a
     value from 1 second to 600 seconds (1800 for GPU).
     The default value is 10 seconds.

   - For **Failure threshold**, specify the number of times to retry the
     probe before shutting down the container. The default value is 3.

   - For **Timeout** , specify the number of seconds to wait until the probe
     times out. This value cannot exceed the value specified for `periodSeconds`.
     Specify a value from 1 to
     600 (1800 for GPU). The default is 1.

8. Click **Add** to add the new threshold.

9. Click **Create** for a new service. Click **View diff \& redeploy** , then **Deploy changes** for an existing service.

To delete a probe, click the **Delete** icon for the health check you want
to delete, then click **Confirm** . To deploy a new revision of your Cloud Run
service, click **View diff \& redeploy** , then **Deploy changes**.

### gcloud

### TCP startup

Run the following command:

      gcloud run deploy SERVICE \
          --image=IMAGE_URL \
          --startup-probe tcpSocket.port=CONTAINER_PORT,initialDelaySeconds=DELAY,failureThreshold=THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

<br />

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
- <var translate="no">DELAY</var>: number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
- <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
- <var translate="no">PERIOD</var>: period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.

<br />

### HTTP startup


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Run the following command:

      gcloud run deploy SERVICE \
          --image=IMAGE_URL \
          --startup-probe httpGet.path=PATH,httpGet.port=CONTAINER_PORT,initialDelaySeconds=DELAY,failureThreshold=THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

<br />

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- <var translate="no">PATH</var>: a relative path to the HTTP endpoint, for example, `/health`.
- Optional. <var translate="no">CONTAINER_PORT</var>: set to the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
- Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
- Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for periodSeconds. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.

<br />

### gRPC startup


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Run the following command:

      gcloud run deploy SERVICE \
          --image=IMAGE_URL \
          --startup-probe grpc.port=CONTAINER_PORT,grpc.service=GRPC_SERVICE,initialDelaySeconds=DELAY,failureThreshold=THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

<br />

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
- Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
- Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
- Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for periodSeconds. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.

<br />

### YAML

### TCP startup

1. 
2. Configure the `startupProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
    name: SERVICE
   spec:
    template:
      metadata:
      spec:
        containers:
        - image: IMAGE_URL
          startupProbe:
            tcpSocket:
              port: CONTAINER_PORT
            initialDelaySeconds: DELAY
            timeoutSeconds: TIMEOUT
            failureThreshold: THRESHOLD
            periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
   - <var translate="no">DELAY</var>: number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
   - <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
   - <var translate="no">PERIOD</var>: period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.
3. 

### HTTP startup


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

1. 
2. Configure the `startupProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           startupProbe:
             httpGet:
               path: PATH
               port: CONTAINER_PORT
               httpHeaders:
                 - name: HEADER_NAME
                   value: HEADER_VALUE
             initialDelaySeconds: DELAY
             timeoutSeconds: TIMEOUT
             failureThreshold: THRESHOLD
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - <var translate="no">PATH</var>: a relative path to the HTTP endpoint, for example, `/health`.
   - Optional. <var translate="no">CONTAINER_PORT</var>: set to the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
   - Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
   - Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
   - Optional: `httpHeaders` can be used to supply multiple or repeated custom headers using the <var translate="no">HEADER_NAME</var> and <var translate="no">HEADER_VALUE</var> fields as shown.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for periodSeconds. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.
3. 

### gRPC startup


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

1. 
2. Configure the `startupProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           startupProbe:
             grpc:
               service: GRPC_SERVICE
               port: CONTAINER_PORT
             initialDelaySeconds: DELAY
             timeoutSeconds: TIMEOUT
             failureThreshold: THRESHOLD
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
   - Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
   - Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
   - Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for periodSeconds. Specify a value from 1 to 600 (1800 for GPU). The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 600 seconds (1800 for GPU). The default value is 10 seconds.
3. 

### Terraform

To learn how to apply or remove a Terraform configuration, see
[Basic Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands).

### TCP startup

Configure your Cloud Run service with `startup_probe` attribute as shown:

    resource "google_cloud_run_v2_service" "default" {
      name     = "cloudrun-service-healthcheck"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          image = "us-docker.pkg.dev/cloudrun/container/hello"

          startup_probe {
            failure_threshold     = 5
            initial_delay_seconds = 10
            timeout_seconds       = 3
            period_seconds        = 3

            tcp_socket {
              port = 8080
            }
          }
        }
      }
    }

### HTTP startup


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Configure your Cloud Run service with `startup_probe` attribute as shown:

    resource "google_cloud_run_v2_service" "default" {
      name     = "cloudrun-service-healthcheck"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          image = "us-docker.pkg.dev/cloudrun/container/hello"

          startup_probe {
            failure_threshold     = 5
            initial_delay_seconds = 10
            timeout_seconds       = 3
            period_seconds        = 3

            http_get {
              path = "/"
              # Custom headers to set in the request
              # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#http_headers
              http_headers {
                name  = "Access-Control-Allow-Origin"
                value = "*"
              }
            }
          }
        }
      }
    }

### gRPC startup


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Configure your Cloud Run service with `startup_probe` attribute as shown:

    resource "google_cloud_run_v2_service" "default" {
      name     = "cloudrun-service-healthcheck"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          # Note: Change to the name of your image
          image = "us-docker.pkg.dev/cloudrun/container/hello"

          startup_probe {
            failure_threshold     = 5
            initial_delay_seconds = 10
            timeout_seconds       = 3
            period_seconds        = 3

            grpc {
              # Note: Change to the name of your pre-existing grpc health status service
              service = "grpc.health.v1.Health"
            }
          }
        }
      }
    }

### The default TCP startup probe

If you don't explicitly configure a TCP startup probe for a new
Cloud Run service, Cloud Run automatically configures a
TCP startup probe with the following default values:

    startupProbe:
              timeoutSeconds: 240
              periodSeconds: 240
              failureThreshold: 1

You can change these default values following the instructions in the
[probe configuration](https://docs.cloud.google.com/run/docs/configuring/healthchecks#startup-probes) section on this page.

### Startup probe requirements and behavior

| Probe Type | Requirements | Behavior |
|---|---|---|
| TCP startup | None | By default, Cloud Run makes a TCP connection to open the TCP Socket on the specified port. If Cloud Run is unable to establish a connection, it indicates a failure. If a startup probe does not succeed within the specified time (`failureThreshold` \* `periodSeconds`), which cannot exceed 600 seconds (1800 for GPU), the container is shut down. See also [TCP defaults](https://docs.cloud.google.com/run/docs/configuring/healthchecks#tcp-startup-probe). |
| HTTP startup | Create an HTTP health check endpoint Use HTTP/1 | After probe configuration, Cloud Run makes an HTTP GET request to the health check endpoint (for example, `/health`). Any `2XX` or `3XX` response is a success, everything else indicates failure. If a startup probe does not succeed within the specified time (`failureThreshold` \* `periodSeconds`), which cannot exceed 600 seconds (1800 for GPU), the container is shut down. If the HTTP startup probe succeeds within the specified time, and you have configured an HTTP liveness probe, the HTTP liveness probe is started. |
| gRPC startup | Implement the [gRPC Health Checking protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md) in your Cloud Run service | If a startup probe does not succeed within the specified time (`failureThreshold` \* `periodSeconds`), which cannot exceed 600 seconds (1800 for GPU), the container is shut down. |

## Configure liveness probes

Any configuration change leads to the
creation of a new revision. Subsequent revisions will also automatically get
this configuration setting unless you make explicit updates to change it.

You can configure HTTP and gRPC probes using Google Cloud console, YAML, or Terraform:

### Console

1. In the Google Cloud console, go to Cloud Run:

   [Go to Cloud Run](https://console.cloud.google.com/run)
2. Select **Services** from the Cloud Run navigation menu.

3. If you are configuring a new service, click **Deploy container** ,
   fill out the initial service settings page, then click **Containers, Networking, Security**
   to expand the service configuration page.

4. If you are configuring an existing service, click the service, then click
   the **Containers** tab.

5. In the **Health checks** section, click **Add health check** to open the
   **Add health check** configuration panel.

6. From the **Select health check type** menu, select **Liveness check**.

7. From the **Select probe type** menu, select the type of the probe you want
   to use, for example, HTTP or gRPC. This displays the probe configuration form.

8. Probe configuration varies by probe type. Configure the probe settings:

   - If you are using HTTP probes:

     - Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your service code to respond to the probe. The endpoint name (for example, `/startup`, `/health` or `/are_you_ready`) must match the `path` in the probe configuration. HTTP health check endpoints are externally accessible and follow the same principles as any other externally exposed HTTP service endpoints.
     - Use the **Path** field to specify the relative path to the endpoint, for example, `/`.
     - Select the **HTTP Headers** checkbox to specify optional custom headers. Specify the header name in the **Name** field and header value in the **Value** field. Click **Add HTTP header** to specify more headers.
   - If you are using gRPC probes:

     - Ensure that your container image implements the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
   - For **Port** , specify the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port)
     used for your service.

   - For **Initial delay**, specify the number of seconds to wait after the
     container has started before performing the first probe. Specify a value
     from 0 seconds to 600 seconds (1800 for GPU).
     The default value is 0 seconds.

   - For **Period** , specify the period (in seconds) at which to perform the
     probe. For example `2` to perform the probe every 2 seconds.
     Specify a value from 1 second to
     3600 seconds. The default value is
     10 seconds.

   - For **Failure threshold**, specify the number of times to retry the
     probe before shutting down the container. The default value is
     3.

   - For **Timeout** , specify the number of seconds to wait until the probe
     times out. This value cannot exceed the value specified for `periodSeconds`.
     Specify a value from 1 to
     3600. The default is
     1.

9. Click **Add** to add the new threshold.

10. Click **Create** for a new service. Click **View diff \& redeploy** , then **Deploy changes** for an existing service.

To delete a probe, click the **Delete** icon for the health check you want
to delete, then click **Confirm** . To deploy a new revision of your Cloud Run
service, click **View diff \& redeploy** , then **Deploy changes**.

### gcloud

### HTTP liveness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Run the following command:

      gcloud run deploy SERVICE \
          --image=IMAGE_URL \
          --liveness-probe httpGet.path=PATH,httpGet.port=CONTAINER_PORT,initialDelaySeconds=DELAY,failureThreshold=THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

<br />

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- <var translate="no">PATH</var>: a relative path to the HTTP endpoint, for example, `/health`.
- Optional. <var translate="no">CONTAINER_PORT</var>: set to the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
- Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
- Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 3600.The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 3600 seconds. The default value is 10 seconds.

<br />

### gRPC liveness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Run the following command:

      gcloud run deploy SERVICE \
          --image=IMAGE_URL \
          --liveness-probe grpc.port=CONTAINER_PORT,grpc.service=GRPC_SERVICE,initialDelaySeconds=DELAY,failureThreshold=THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

<br />

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
- Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
- Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
- Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 3600.The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 3600 seconds. The default value is 10 seconds.

<br />

### YAML

### HTTP liveness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

1. 
2. Configure the `livenessProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           livenessProbe:
             httpGet:
               path: PATH
               port: CONTAINER_PORT
               httpHeaders:
                 - name: HEADER_NAME
                   value: HEADER_VALUE
             initialDelaySeconds: DELAY
             timeoutSeconds: TIMEOUT
             failureThreshold: THRESHOLD
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - <var translate="no">PATH</var>: a relative path to the HTTP endpoint, for example, `/health`.
   - Optional. <var translate="no">CONTAINER_PORT</var>: set to the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
   - Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
   - Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
   - Optional: `httpHeaders` can be used to supply multiple or repeated custom headers using the <var translate="no">HEADER_NAME</var> and <var translate="no">HEADER_VALUE</var> fields as shown.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 3600.The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 3600 seconds. The default value is 10 seconds.
3. 

### gRPC liveness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

1. 
2. Configure the `livenessProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           livenessProbe:
             grpc:
               port: CONTAINER_PORT
               service: GRPC_SERVICE
             initialDelaySeconds: DELAY
             timeoutSeconds: TIMEOUT
             failureThreshold: THRESHOLD
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
   - Optional. <var translate="no">CONTAINER_PORT</var>: the [container port](https://docs.cloud.google.com/run/docs/configuring/services/containers#configure-port) used for your service.
   - Optional. <var translate="no">DELAY</var>: the number of seconds to wait after the container has started before performing the first probe. Specify a value from 0 seconds to 600 seconds (1800 for GPU). The default value is 0 seconds.
   - Optional. <var translate="no">THRESHOLD</var>: the number of times to retry the probe before shutting down the container. The default value is 3.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 3600.The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 second to 3600 seconds. The default value is 10 seconds.

   <br />

3. 

### Terraform

To learn how to apply or remove a Terraform configuration, see
[Basic Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands).

### HTTP liveness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Configure your Cloud Run service with `liveness_probe` attribute as shown:

    resource "google_cloud_run_v2_service" "default" {
      name     = "cloudrun-service-healthcheck"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          image = "us-docker.pkg.dev/cloudrun/container/hello"

          liveness_probe {
            failure_threshold     = 5
            initial_delay_seconds = 10
            timeout_seconds       = 3
            period_seconds        = 3

            http_get {
              path = "/"
              # Custom headers to set in the request
              # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#http_headers
              http_headers {
                name  = "Access-Control-Allow-Origin"
                value = "*"
              }
            }
          }
        }
      }
    }

### gRPC liveness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Configure your Cloud Run service with `liveness_probe` attribute as shown:

    resource "google_cloud_run_v2_service" "default" {
      name     = "cloudrun-service-healthcheck"
      location = "us-central1"

      deletion_protection = false # set to "true" in production

      template {
        containers {
          # Note: Change to the name of your image
          image = "us-docker.pkg.dev/cloudrun/container/hello"

          liveness_probe {
            failure_threshold     = 5
            initial_delay_seconds = 10
            timeout_seconds       = 3
            period_seconds        = 3

            # Note: Change to the name of your pre-existing grpc health status service
            grpc {
              service = "grpc.health.v1.Health"
            }
          }
        }
      }
    }

### Liveness probe requirements and behavior

| Probe Type | Requirements | Behavior |
|---|---|---|
| HTTP liveness | Create an HTTP health check endpoint Use HTTP/1 | The liveness probe starts only after the startup probe is successful. After probe configuration, and any startup probe is successful, Cloud Run makes an HTTP GET request to the health check endpoint (for example, `/health`). Any `2XX` or `3XX` response is a success, everything else indicates failure. If a liveness probe does not succeed within the specified time (`failureThreshold` \* `periodSeconds`), the container is shut down using a `SIGKILL` signal. Any remaining requests that were still being served by the container are terminated with the HTTP status code `503`. After the container is shut down, Cloud Run autoscaling starts up a new container instance. |
| gRPC liveness | Implement the [gRPC Health Checking protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md) in your Cloud Run service | If you configure a gRPC startup probe, the liveness probe starts only after the startup probe is successful. After the liveness probe is configured, and any startup probe is successful, Cloud Run makes a health check request to the service. If a liveness probe does not succeed within the specified time (`failureThreshold` \* `periodSeconds`), the container is shut down using a `SIGKILL` signal. After the container is shut down, Cloud Run autoscaling starts up a new container instance. |

## Configure readiness probes

Any configuration change leads to the
creation of a new revision. Subsequent revisions will also automatically get
this configuration setting unless you make explicit updates to change it.

The following limitations apply to readiness probes:

- If you enable session affinity, Cloud Run continues to send
  requests to the same instance, even if its readiness check fails.

- If you previously configured a readiness probe for your Cloud Run
  service using the Cloud Run Admin API v1 before November 2025, your readiness
  checks won't take effect even after you deploy a new configuration for that
  service. This occurs because the service retains an older configuration.
  Services you create after November 2025, or those that never used a readiness
  probe, are unaffected. To enable supported readiness probes on affected
  services, do the following:

  1. Deploy a new revision that removes the older readiness probe definition.

  2. Deploy another new revision that adds the relevant readiness probe
     definition.

  These steps clear any older configuration and enable the readiness probe
  functionality.

You can configure a readiness probe using the Google Cloud console, the Google Cloud CLI
or YAML:

### Console

1. In the Google Cloud console, go to Cloud Run:

   [Go to Cloud Run](https://console.cloud.google.com/run)
2. Select **Services** from the Cloud Run navigation menu.

3. If you are configuring a new service, click **Deploy container** ,
   fill out the initial service settings page, then click **Containers, Networking, Security**
   to expand the service configuration page.

4. If you are configuring an existing service, click the service, then click
   the **Containers** tab.

5. In the **Health checks** section, click **Add health check** to open the
   **Add health check** configuration panel.

6. From the **Select health check type** menu, select **Readiness check**.

7. From the **Select probe type** menu, select the type of the probe
   you want to use, for example, HTTP or gRPC. This displays the probe configuration
   form.

8. Probe configuration varies by probe type. Configure the probe settings:

   - If you are using HTTP probes:

     -
       Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
       service code to respond to the probe. The endpoint name (for example, `/startup`,
       `/health` or `/are_you_ready`) must match the `path` in
       the probe configuration. HTTP health check endpoints are externally accessible
       and follow the same principles as any other externally exposed HTTP service
       endpoints.

     - Use the **Path** field to specify the relative path to the endpoint,
       for example, `/are_you_ready`. The default path is `/`.

   - If you are using gRPC probes:

     - Ensure that your container image implements the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
   - For **Port**, specify the container port for your service. The default
     port is the main ingress port.

   - For **Period** , specify the period (in seconds) at which to perform
     the probe. For example `2` to perform the probe every 2 seconds.
     Specify a value from 1 to 300. The default value is 10 seconds.

   - For **Success threshold**, specify the minimum consecutive successes
     for the probe to be considered successful after failure. The default
     is 2.

   - For **Failure threshold**, specify the number of times to retry the
     probe before reporting a failure, which causes the instance to stop
     receiving traffic. The default value is
     3.

   - For **Timeout** , specify the number of seconds to wait until the
     probe times out. This value cannot exceed the value specified for
     `periodSeconds`. Specify a value from
     1 to 300. The default is 1.

9. Click **Add** to add the new threshold.

10. Click **Create** for a new service. Click **View diff \& redeploy** , then **Deploy changes** for an existing service.

To delete a probe, click the **Delete** icon for the health check you want
to delete, then click **Confirm** . To deploy a new revision of your Cloud Run
service, click **View diff \& redeploy** , then **Deploy changes**.

### gcloud

### HTTP readiness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Run the following command:

    gcloud run deploy SERVICE \
        --image=IMAGE_URL \
        --readiness-probe httpGet.path=PATH,httpGet.port=CONTAINER_PORT,successThreshold=SUCCESS_THRESHOLD,failureThreshold=FAILURE_THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">PATH</var>: the relative path to the HTTP endpoint, for example, `/are_you_ready`. The default path is `/`.
- Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
- Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
- Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.

### gRPC readiness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Run the following command:

    gcloud run deploy SERVICE \
        --image=IMAGE_URL \
        --readiness-probe grpc.port=CONTAINER_PORT,grpc.service=GRPC_SERVICE,successThreshold=SUCCESS_THRESHOLD,failureThreshold=FAILURE_THRESHOLD,timeoutSeconds=TIMEOUT,periodSeconds=PERIOD

Replace the following:

- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
- Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
- Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
- Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.

### YAML

### HTTP readiness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

1. 
2. Configure the `readinessProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           readinessProbe:
             httpGet:
               path: PATH
               port: CONTAINER_PORT
             successThreshold: SUCCESS_THRESHOLD
             failureThreshold: FAILURE_THRESHOLD
             timeoutSeconds: TIMEOUT
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - Optional. <var translate="no">PATH</var>: the relative path to the HTTP endpoint, for example, `/are_you_ready`. The default path is `/`.
   - Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
   - Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
   - Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.
3. 

### gRPC readiness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

1. 
2. Configure the `readinessProbe` attribute as shown:

   ```yaml
   apiVersion: serving.knative.dev/v1
   kind: Service
   metadata:
     name: SERVICE
     annotations:
       run.googleapis.com/launch-stage: BETA
   spec:
     template:
       metadata:
       spec:
         containers:
         - image: IMAGE_URL
           readinessProbe:
             grpc:
               port: CONTAINER_PORT
               service: GRPC_SERVICE
             successThreshold: SUCCESS_THRESHOLD
             failureThreshold: FAILURE_THRESHOLD
             timeoutSeconds: TIMEOUT
             periodSeconds: PERIOD
   ```

   Replace the following:
   - <var translate="no">SERVICE</var>: the name of your Cloud Run service.
   - <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
   - Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
   - Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
   - Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
   - Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
   - Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
   - Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.
3. 

### Terraform

To learn how to apply or remove a Terraform configuration, see
[Basic Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands).

### HTTP readiness


Add an HTTP/1 endpoint (the Cloud Run default, not HTTP/2) in your
service code to respond to the probe. The endpoint name (for example, `/startup`,
`/health` or `/are_you_ready`) must match the `path` in
the probe configuration. HTTP health check endpoints are externally accessible
and follow the same principles as any other externally exposed HTTP service
endpoints.

Configure your Cloud Run service with the `readiness_probe` attribute as shown:

```terraform
resource "google_cloud_run_v2_service" "default" {
  name     = "SERVICE"
  location = "REGION"
  deletion_protection = false # set to "true" in production

  template {
    containers {
      image = "IMAGE_URL"

      readiness_probe {
        timeout_seconds   = TIMEOUT
        period_seconds    = PERIOD
        success_threshold = SUCCESS_THRESHOLD
        failure_threshold = FAILURE_THRESHOLD

        http_get {
          path = "PATH"
          port = CONTAINER_PORT
        }
      }
    }
  }
}
```

Replace the following:

- <var translate="no">REGION</var>: the Google Cloud region---for example, `us-central1`.
- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">PATH</var>: the relative path to the HTTP endpoint, for example, `/are_you_ready`. The default path is `/`.
- Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
- Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
- Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.

### gRPC readiness


Ensure that your container image implements
the [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).

Configure your Cloud Run service with the `readiness_probe` attribute as shown:

```terraform
resource "google_cloud_run_v2_service" "default" {
  name     = "SERVICE"
  location = "REGION"
  deletion_protection = "true"

  template {
    containers {
      image = "IMAGE_URL"

      readiness_probe {
        timeout_seconds   = TIMEOUT
        period_seconds    = PERIOD
        success_threshold = SUCCESS_THRESHOLD
        failure_threshold = FAILURE_THRESHOLD

        grpc {
          service = "GRPC_SERVICE"
          port = CONTAINER_PORT
        }
      }
    }
  }
}
```

Replace the following:

- <var translate="no">REGION</var>: the Google Cloud region---for example, `us-central1`.
- <var translate="no">SERVICE</var>: the name of your Cloud Run service.
- <var translate="no">IMAGE_URL</var>: a reference to the container image, for example, `us-docker.pkg.dev/cloudrun/container/hello:latest`. If you use Artifact Registry, the repository <var translate="no">REPO_NAME</var> must already be created. The URL has the shape `LOCATION-docker.pkg.dev/PROJECT_ID/REPO_NAME/PATH:TAG`.
- Optional. <var translate="no">CONTAINER_PORT</var>: the container port used for your service. The default port is the main ingress port.
- Optional. <var translate="no">GRPC_SERVICE</var>: If set, this is used in the service field of the `grpc.health.v1.HealthCheckRequest` when the `grpc.health.v1.Health.Check` rpc is called.
- Optional. <var translate="no">SUCCESS_THRESHOLD</var>: the minimum consecutive successes for the probe to be considered successful after failure. The default is 2.
- Optional. <var translate="no">FAILURE_THRESHOLD</var>: the number of times to retry the probe before reporting a failure, which causes the instance to stop receiving traffic. The default is 3.
- Optional. <var translate="no">TIMEOUT</var>: the number of seconds to wait until the probe times out. This value cannot exceed the value specified for `periodSeconds`. Specify a value from 1 to 300. The default is 1.
- Optional. <var translate="no">PERIOD</var>: the period (in seconds) at which to perform the probe. For example `2` to perform the probe every 2 seconds. Specify a value from 1 to 300. The default value is 10 seconds.

### Readiness probe requirements and behavior

| Probe Type | Requirements | Behavior |
|---|---|---|
| HTTP readiness | Create an HTTP health check endpoint Use HTTP/1 | The readiness probe starts only after the startup probe is successful. After probe configuration, and any startup probe is successful, Cloud Run makes an HTTP GET request to the health check endpoint (for example, `/are_you_ready`). Any `2XX` or `3XX` response is a success, everything else indicates failure. If an instance fails its readiness probe beyond the configured `failureThreshold`, Cloud Run stops routing new requests to the instance without shutting it down, and resumes routing requests once the instance passes its readiness probe (`successThreshold` consecutive times). |
| gRPC readiness | Implement the [gRPC Health Checking protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md) in your Cloud Run service | The readiness probe starts only after any configured startup probe is successful. Cloud Run makes a gRPC health check request to the service. If an instance fails its readiness probe beyond the configured `failureThreshold`, Cloud Run stops routing new requests to the instance without shutting it down, and resumes routing requests once the instance passes its readiness probe (`successThreshold` consecutive times). |

## CPU allocation

- CPU is always allocated when probes run.
- All probes are billed for CPU and memory usage consumption, but there is no request-based charge.

## What's next

- Learn how to configure a [gRPC health check protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
- [Automate cross-regional failover with Cloud Run service health](https://docs.cloud.google.com/run/docs/multiple-regions#service-health).