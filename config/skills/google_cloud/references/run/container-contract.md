This page lists key requirements and behaviors of containers in
Cloud Run. The page also calls out the differences between Cloud Run
services, Cloud Run jobs, and Cloud Run worker pools where appropriate.

## Supported languages and images

Your container image can run code written in the programming language of your
choice and use any base image, provided that it respects the constraints
listed in this page.

Executables in the container image must be compiled for Linux 64-bit.
Cloud Run specifically supports the Linux x86_64 ABI format.

Cloud Run accepts container images in the Docker Image Manifest V2,
[Schema 1](https://docs.docker.com/registry/spec/manifest-v2-1/),
[Schema 2](https://docs.docker.com/registry/spec/manifest-v2-2/), and
[OCI](https://github.com/opencontainers/image-spec) image formats.
Cloud Run also accepts Zstd compressed container images.

If deploying a [multi-architecture image](https://www.docker.com/blog/multi-arch-build-and-images-the-simple-way/),
the [manifest list](https://docs.docker.com/registry/spec/manifest-v2-2/#manifest-list)
must include `linux/amd64`.

For functions deployed with Cloud Run, you can use one of the
[Cloud Run runtime base images](https://docs.cloud.google.com/run/docs/configuring/services/runtime-base-images)
that are published by Google Cloud's buildpacks to receive automatic security and
maintenance updates. See the
[Runtime support schedule](https://docs.cloud.google.com/run/docs/runtime-support) the supported runtimes.

## Container requirements

When deploying containers to Cloud Run, the following requirements must
be met:

### Container deployed to services must listen for requests on the correct port

A Cloud Run service starts Cloud Run *instances* to handle incoming requests.
A Cloud Run instance always has one single ingress container that listens for
requests, and optionally one or more sidecar containers. The following port
configuration details apply only to the ingress container, not to sidecars.

The ingress container within an instance must listen for requests on
`0.0.0.0` on the port to which requests are sent.
Notably, the ingress container should *not* listen on `127.0.0.1`.
By default, requests are sent to `8080`, but you can [configure Cloud Run](https://docs.cloud.google.com/run/docs/configuring/services/containers#command-line)
to send requests to the port of your choice. Cloud Run injects the
`PORT` environment variable into the ingress container.

## VPC network connectivity

Cloud Run services and jobs support [Direct VPC
*egress*](https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc). This means that they can send
traffic to private resources within your configured VPC network, such as
databases or internal services. Cloud Run services and jobs don't
support Direct VPC *ingress*.

Cloud Run worker pools support both Direct VPC
[*egress* and Direct VPC *ingress*](https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc#direct-vpc-workerpool). When you configure Direct VPC
for your Cloud Run worker pool deployment, each worker
instance receives a private IP address on the configured network and subnet.
Only resources from your VPC network can connect to the worker pool private IP address endpoint.
For more information about obtaining the private IP addresses of your worker pool
instance, see [Retrieve the private IP addresses using the metadata server
(MDS)](https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc#mds-support).

For Cloud Run worker pools with Direct VPC ingress, such as database
connections or any other custom TCP-based protocol, the container must listen
for TCP connections on the port exposed in your container image through the
Dockerfile or specified by the `PORT` environment variable.

### Container running in a job execution must exit upon completion

For Cloud Run jobs, the container must exit with exit code 0 when the
job has successfully completed, and exit with a non-zero exit code when the job
has failed.

Because jobs shouldn't serve requests, the container shouldn't listen on a port or
start a web server.

## Transport layer encryption (TLS)

The container shouldn't implement any transport layer security directly. TLS is
terminated by Cloud Run for HTTPS and gRPC, and then requests are proxied as
HTTP/1 or gRPC to the container without TLS.

If you [configure a Cloud Run service](https://docs.cloud.google.com/run/docs/configuring/http2#setting) to
use HTTP/2 end-to-end, your container must handle requests in HTTP/2 cleartext
(h2c) format, because TLS is still terminated automatically by Cloud Run.

## Responses (services)

For Cloud Run services, your container must send a response
within the time specified in the
[request timeout setting](https://docs.cloud.google.com/run/docs/configuring/request-timeout#setting) after it
receives a request, including the container startup time.
Otherwise the request is ended and a 504 error is returned.

### Response caching and cookies

If your Cloud Run service's response contains a `Set-Cookie`
header, Cloud Run sets the `Cache-Control` header to `private` so
that the response is not cached. This prevents other users from retrieving the
cookie.

## Environment variables

Different sets of environment variables are available for Cloud Run
services and jobs.

### Environment variables for services

The following environment variables are automatically added to all the running
containers except `PORT`. The `PORT` variable is only added to the ingress container:

| Name | Description | Example |
|---|---|---|
| `PORT` | The port your HTTP server should listen on. | `8080` |
| `K_SERVICE` | The name of the Cloud Run service being run. | `hello-world` |
| `K_REVISION` | The name of the Cloud Run revision being run. | `hello-world.1` |
| `K_CONFIGURATION` | The name of the Cloud Run configuration that created the revision. | `hello-world` |

### Environment variables for jobs

For Cloud Run jobs, the following environment variables are set:

| Name | Description | Example |
|---|---|---|
| `CLOUD_RUN_JOB` | The name of the Cloud Run job being run. | `hello-world` |
| `CLOUD_RUN_EXECUTION` | The name of the Cloud Run execution being run. | `hello-world-abc` |
| `CLOUD_RUN_TASK_INDEX` | The index of this task. Starts at 0 for the first task and increments by 1 for every successive task, up to the maximum number of tasks minus 1. If you set `--parallelism` to greater than 1, tasks might not follow the index order. For example, it would be possible for task 2 to start before task 1. | `0` |
| `CLOUD_RUN_TASK_ATTEMPT` | The number of times this task has been retried. Starts at 0 for the first attempt and increments by 1 for every successive retry, up to the maximum retries value. | `0` |
| `CLOUD_RUN_TASK_COUNT` | The number of tasks defined in the `--tasks` parameter. | `1` |

### Environment variables for worker pools

Cloud Run sets the following environment variables for worker pools:

| Name | Description | Example |
|---|---|---|
| `CLOUD_RUN_WORKER_POOL` | The name of the running Cloud Run worker pool. | `hello-world` |
| `CLOUD_RUN_REVISION` | The name of the running Cloud Run worker pool revision. | `hello-world.1` |

## Request and response header requirements (services)

For services, Cloud Run restricts header names to printable non-whitespace ASCII, and cannot
contain colons. Cloud Run restricts header values to visible ASCII characters, plus
space and horizontal tab, according to
[IETF RFC 7230](https://tools.ietf.org/html/rfc7230#section-3.2).

## File system access

Each container's file system is writable and subject to the following
behavior:

- It is an in-memory file system, so writing to it uses the instance's memory.
- Data written to the file system doesn't persist when the instance stops.

You cannot specify a size limit for this files system, so you can
potentially use up all the memory allocated to your instance by writing
to the in-memory file system, which will crash the instance. You can avoid this
issue if you use a dedicated [in-memory volume](https://docs.cloud.google.com/run/docs/configuring/in-memory-volumes)
with a size limit.

## Instance lifecycle

Lifecycle characteristics differ for Cloud Run jobs and services, so
these are described separately in the following subsections.

### For services

The following characteristics apply to services only.

#### Service scaling

By default, a Cloud Run service is
[automatically scaled](https://docs.cloud.google.com/run/docs/about-instance-autoscaling) to the number of
instances needed to handle all incoming requests, events, or
CPU utilization. You can optionally use [manual scaling](https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling)
if you need more control over your scaling behavior.

Every instance runs a fixed number
of containers -- one ingress container and optionally one or more sidecar containers.

When a revision does not receive any traffic, it is scaled in to the
[minimum number of instances configured](https://docs.cloud.google.com/run/docs/configuring/min-instances)
(zero by default).

#### Startup

For Cloud Run services, your instances must listen for requests within
4 minutes after being started and all containers within
the instance need to be healthy.
During this startup time, instances are allocated CPU. You can
[enable startup CPU boost](https://docs.cloud.google.com/run/docs/configuring/services/cpu#startup-boost) to
temporarily increase CPU allocation during instance startup in order
to reduce startup latency.

Requests will be sent to the ingress container as soon as it is [listening on
the configured port](https://docs.cloud.google.com/run/docs/container-contract#port).

A request waiting for an instance will be kept pending in a queue as
follows:

Requests will pend for up to 3.5 times average startup time of container instances of this service, or 10 seconds, whichever is greater.

You can configure a [startup probe](https://docs.cloud.google.com/run/docs/configuring/healthchecks) to
determine whether the container has started and is ready to serve requests.

For a Cloud Run service consisting of multi-container instances, you can specify the sequence in which
the containers are started within the instance by configuring the [container startup order](https://docs.cloud.google.com/run/docs/configuring/services/containers#container-ordering).

#### Processing a request

For Cloud Run services, CPU is always allocated to all containers
including sidecars within an instance as long as the Cloud Run
revision is processing at least one request.

#### Idle

For Cloud Run services, an idle instance is one that is not
processing any requests.

The CPU allocated to all containers in an idle instance depends on the
configured [billing settings](https://docs.cloud.google.com/run/docs/configuring/billing-settings).

Unless an instance must be kept idle due to
the [minimum number of instances](https://docs.cloud.google.com/run/docs/configuring/min-instances)
configuration setting, it won't be kept idle for longer than 15 minutes.

#### Shutdown

For Cloud Run services, an idle instance can be shut down at any time, including
[instances kept warm due to a configured minimum number of instances](https://docs.cloud.google.com/run/docs/configuring/min-instances).
If an instance that is processing requests needs to be shut down,
requests already being processed are given time to complete, and new incoming requests are routed to other instances. In exceptional cases, Cloud Run might initiate a shutdown and send a
SIGTERM signal to a container that is still processing requests.

Before shutting down an instance, Cloud Run sends a `SIGTERM` signal to all the containers in an instance,
indicating the start of a 10 second period
before the actual shutdown occurs, at which point Cloud Run sends a `SIGKILL` signal.
During this period, the instance is allocated CPU and billed.
In services that use the first generation execution environment, if the
instance does not trap the `SIGTERM` signal, it is
immediately shut down. In services that use the second generation execution
environment, we recommend installing a
[`SIGTERM` handler](https://docs.cloud.google.com/run/docs/about-execution-environments#best-practices) on
your container to receive a warning when Cloud Run is about to shut
down an instance.

#### Forced termination

If one or more Cloud Run containers exceed the
[total container memory limit](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits),
the instance is terminated. All requests that are still processing on the instance
end with an `HTTP 500` error.

### For jobs

For Cloud Run jobs, container instances run until the container
instance exits, or until the [task timeout](https://docs.cloud.google.com/run/docs/configuring/task-timeout)
is reached or until the container crashes.

#### Exit codes

You can use job exit codes to see whether the job completed successfully or
whether it encountered any errors. The exit codes are numerical values that map
to successful completion or specific types of errors.

The following table specifies common exit codes and their definitions:

| Exit code | Signal | Description |
|---|---|---|
| 0 |   | Task completed successfully. |
| 4 | `SIGILL` | Task attempted to access memory at an incorrect address. |
| 7 | `SIGBUS` | Task attempted to access memory outside its allocated boundaries. |
| 9 | `SIGKILL` | Task is forcibly terminated, either by user action or manual intervention. |
| 11 | `SIGSEGV` | Task tried to access unauthorized memory. |
| 15 | `SIGTERM` | When a task exceeds its configured timeout or if the task is canceled, it receives a `SIGTERM` signal. The application server sends the `SIGTERM` signal for the container instance to shut down. If the instance doesn't shut down on its own within a few seconds after receiving `SIGTERM`, Cloud Run sends a `SIGKILL` signal for a [forced termination](https://docs.cloud.google.com/run/docs/container-contract#forced-termination-jobs). If the instance exits correctly with `SIGTERM`, it might report a different error code; otherwise, it returns `SIGTERM`. |

#### Forced termination

A Cloud Run container instance that exceeds the
[allowed memory limit](https://docs.cloud.google.com/run/docs/configuring/jobs/memory-limits)
is terminated. All requests that are still processing on the container instance
end with an `HTTP 500` error.

If a task exceeds the [task timeout](https://docs.cloud.google.com/run/docs/configuring/task-timeout),
Cloud Run sends a `SIGTERM` signal indicating the start of a
10 second period before the actual shutdown
occurs, at which point Cloud Run sends a
`SIGKILL` signal, shutting down the container instance. See
[Shutdown](https://docs.cloud.google.com/run/docs/container-contract#instance-shutdown) for details and recommendations on how to
handle this.

During this period, container instances are allocated CPU for their entire
lifecycle and are billed.

### For worker pools

The following characteristics apply only to worker pools.

#### Scaling

Worker pools don't automatically scale. [Manually
scale](https://docs.cloud.google.com/run/docs/configuring/workerpools/manual-scaling) the number of instances
that your Cloud Run worker pool requires to handle its workload. By
default, Cloud Run sets the number of instances to `1`. You can change
this number to be higher or lower, or you can disable scaling by setting the
number to 0. To start and remain active, your workload must have at least one
instance. If you set the minimum instances to `0`, the worker instance won't
start, even if the deployment is successful.

#### Startup

Cloud Run worker pools instances start the container with
the entrypoint you specify in the container image or in the worker pool
configuration. All containers in the instance must be healthy.

By default, Cloud Run container instances use one CPU. You can
[increase or decrease](https://docs.cloud.google.com/run/docs/configuring/workerpools/cpu) this value based
on your requirements.

You can configure a [startup probe](https://docs.cloud.google.com/run/docs/configuring/workerpools/healthchecks)
to determine whether the container started.
The startup probe enables Cloud Run to inspect the health of a dependent
container, making sure it passes successfully before it starts up the next container.
If you don't use health checks, Cloud Run starts containers in the
specified order, even if containers they depend on fail to start.

#### Resource allocation

Worker pools don't idle. Regardless of
its state, Cloud Run always allocates CPU to to all containers,
including sidecars within a worker pool instance.
As long as it's running, an instance is considered active and is billed
accordingly.

#### Shutdown

Cloud Run doesn't scale down worker pool instances based on idle
instances. If a workload-processing instance must be shut down,
Cloud Run gives tasks in-process tasks time to complete and
routes new workloads to other instances. Cloud Run
might also initiate a shutdown and send a `SIGTERM` signal to a container that is still
processing a workload.

Before shutting down an instance, Cloud Run sends a `SIGTERM` signal
to all the containers in an instance. This signal indicates the start of a 10-second period before the actual shutdown
occurs, at which point Cloud Run sends a `SIGKILL` signal.
During this shutdown period, the instance is allocated CPU and billed.
We recommend installing a
[`SIGTERM` handler](https://docs.cloud.google.com/run/docs/about-execution-environments#best-practices) on
your container to receive a warning when Cloud Run is about to shut
down an instance.

#### Forced termination

If one or more Cloud Run containers exceed the
[total container memory limit](https://docs.cloud.google.com/run/docs/configuring/workerpools/memory-limits),
Cloud Run terminates the instance. All requests that are still
processing on the instance end with an `HTTP 500` error.

## Container instance resources

Your container runs under a cgroup controller that restricts CPU, RAM, and other
resources to those configured for your container.

The following sections describe resources for your container instance:

- [CPU](https://docs.cloud.google.com/run/docs/container-contract#cpu)
- [Memory](https://docs.cloud.google.com/run/docs/container-contract#memory)
- [GPU](https://docs.cloud.google.com/run/docs/container-contract#gpu)
- [Concurrency](https://docs.cloud.google.com/run/docs/container-contract#concurrency)

### CPU

Each Cloud Run container in an instance by default gets allocated the *vCPU*
that has been [configured](https://docs.cloud.google.com/run/docs/configuring/services/cpu)
(1 by default). It is possible to configure CPU limits on each container separately.

A vCPU is implemented as an abstraction of underlying
hardware to provide the approximate equivalent CPU time of a single hardware
hyper-thread on variable CPU platforms. All CPU platforms used by Cloud Run
support the [AVX2](https://en.wikipedia.org/wiki/Advanced_Vector_Extensions#Advanced_Vector_Extensions_2)
instruction set. Note that the container contract does not contain any additional CPU platform details.

The container might be executed on multiple cores simultaneously.

For Cloud Run services, CPU allocation depends on the
selected billing.

If you select instance-based billing, CPU is allocated during the life of the
instance. If you select request-based billing (default), CPU is allocated when
instances are processing requests. Refer to
[billing settings](https://docs.cloud.google.com/run/docs/configuring/billing-settings) for details.

If you have configured a number of
[minimum instances](https://docs.cloud.google.com/run/docs/configuring/min-instances), you must use
instance-based billing so that CPU is allocated
[outside of requests](https://docs.cloud.google.com/run/docs/about-instance-autoscaling).

You can [enable startup CPU boost](https://docs.cloud.google.com/run/docs/configuring/services/cpu#startup-boost) to
temporarily increase CPU allocation during instance startup in order
to reduce startup latency.

### Memory

Each Cloud Run container by default gets allocated the memory
that has been [configured](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits),
(512 MiB by default). It is possible to configure memory limits on each container separately.

Typical uses of memory include:

- Code loaded into memory to run the service
- Writing to the file system
- Extra processes running in the container such as an nginx server
- In-memory caching systems such as the PHP [OpCache](https://www.php.net/manual/en/book.opcache.php)
- Per request memory usage
- [Shared in-memory volumes](https://docs.cloud.google.com/run/docs/configuring/in-memory-volumes)

### GPU

You can configure a container in a Cloud Run instance to access a GPU.
If the Cloud Run service is deployed with
sidecar containers, only one container in the deployment can access the GPU. See
[Configure GPU](https://docs.cloud.google.com/run/docs/configuring/services/gpu) for requirements and details.

#### NVIDIA libraries

By default, all of the NVIDIA RTX PRO 6000 Blackwell GPU and NVIDIA L4 GPU driver libraries
are mounted under `/usr/local/nvidia/lib64`. Cloud Run automatically
appends this path to the `LD_LIBRARY_PATH` environment variable
(i.e. `${LD_LIBRARY_PATH}:/usr/local/nvidia/lib64`) of the container with the
GPU. This allows the dynamic linker to find the NVIDIA driver libraries. The
linker searches and resolves paths in the order you list in the `LD_LIBRARY_PATH`
environment variable. Any values you specify in this variable take precedence
over the default Cloud Run driver libraries path `/usr/local/nvidia/lib64`.

If you want to use a CUDA version greater than 13.0,
the easiest way is to depend on a newer [NVIDIA base image](https://catalog.ngc.nvidia.com/containers)
with forward compatibility packages already installed. Another option is to
manually [install the NVIDIA forward compatibility packages](https://docs.nvidia.com/deploy/cuda-compatibility/#installing-the-forward-compatibility-package)
and add them to `LD_LIBRARY_PATH`. Consult [NVIDIA's compatibility matrix](https://docs.nvidia.com/deeplearning/frameworks/support-matrix/index.html)
to determine which CUDA versions are forward compatible with the provided NVIDIA
driver version.

### Concurrency (services)

For Cloud Run services, each Cloud Run instance by default is set to multiple [concurrency](https://docs.cloud.google.com/run/docs/about-concurrency),
where the ingress container can receive more than one request at the same time.
You can change this by [setting concurrency](https://docs.cloud.google.com/run/docs/configuring/concurrency).

## Container security restrictions

The following restrictions apply to containers that run in Cloud Run.
They apply regardless of the Linux user that the container image specifies for
execution.

### Reduced privileges

In Cloud Run, your containers are not granted the root
capabilities of the instance's security boundary. Containers cannot perform actions reserved
for the host, such as the following:

- Adding or removing Linux kernel capabilities
- Using specific kernel capabilities
- Manipulating devices
- Accessing certain hardware resources

Privilege escalation is also disabled in your containers. Use of `sudo` and
`setuid` binaries are not supported in Cloud Run.

Your containers won't have write access to most of the files and directories in
`/dev`, `/proc`, and `/sys`.

There is no Cloud Run equivalent to Docker's `--privileged` mode.

### Container isolation

Cloud Run executes your containers under user, network, PID, and
other Linux namespaces, isolating them from each other and from the instance
itself. This restricts some network capabilities and prevents your root
containers from running as "true root."

### Limited file system mounts from inside containers

The supported path for mounting file systems in Cloud Run is
through the [fully managed volume mounts feature in your Cloud Run container configuration](https://docs.cloud.google.com/run/docs/configuring/services/nfs-volume-mounts).

Other mechanisms of mounting from inside user containers are not supported and
won't work. Unsupported mechanisms include, but aren't limited to, the following:

- Running a mount process inside the container to mount any of the following: NFS, Filestore, SMB/CIFS, or any other network file system.
- Calling system calls that would perform equivalent actions.

In addition, Cloud Run doesn't support nested volume mounts that
mount one volume inside of another volume.

### No alterations to system time

Changing the system time using `adjtimex` and `adjtime` system calls is not
supported, nor are any tools that might permit your container to do so.

### Process and system call restrictions

Basic security profiles, similar to [seccomp security profiles for Docker](https://docs.docker.com/engine/security/seccomp/),
are applied around each of your containers.

Use of eBPF and other kernel-level security features that aren't protected or
limited by Linux namespaces are disabled and not supported for use inside
containers.

Use of other system calls or access system files that require root privileges on
the Cloud Run instance might also be restricted for this reason.

## Container sandbox

If you use the [first generation execution environment](https://docs.cloud.google.com/run/docs/about-execution-environments),
the Cloud Run containers are sandboxed using
the [gVisor](https://gvisor.dev) container runtime sandbox.
As documented in the [gVisor syscall compatibility reference](https://gvisor.dev/docs/user_guide/compatibility/linux/amd64/),
some system calls might not be supported by this container sandbox.

If you use the [second generation execution environment](https://docs.cloud.google.com/run/docs/about-execution-environments),
you have full Linux compatibility.
Cloud Run jobs always use the second generation execution environment.
Within the second generation execution environment,
`/sys/class/dmi/id/product_name` is set to `Google Compute Engine`.

The second generation execution environment runs your service code in a separate
process namespace, so it starts as the container init process which has special
process semantics. In the first generation execution environment, your service
code does not run as the container init process.

### File descriptor limits

Cloud Run first and second generation environments set a limit on
the number of file descriptors a process can open to
25000. This applies to the container and any
child process it creates (forks).
This is a hard limit. If you exceed the limit your instance might run out of
file descriptors/sockets.

### Limits in the second generation environment

Except for the file descriptor limits described earlier,
limits in the second generation environment are standard linux limits.

For example, the limits on the number of file descriptors that can be
opened (as captured in: `/proc/sys/fs/file-max`) use the default value of about
10% of memory. See [`file-max` and `file-nr`](https://docs.kernel.org/admin-guide/sysctl/fs.html#file-max-file-nr)
in the kernel documentation for details.

Similarly, the `max_map_count` (as captured in `/proc/sys/vm/max_map_count`),
which sets the number of memory areas a process can have is using the default
of 65535. See [`max-map-count`](https://docs.kernel.org/admin-guide/sysctl/vm.html#max-map-count)
in the kernel documentation for details.

### Privileged containers and setuid binaries

Cloud Run doesn't support [privileged containers](https://kubernetes.io/docs/concepts/security/pod-security-standards/#privileged). Consequently, Cloud Run doesn't support binaries that use
`setuid` flags for non-root users, such as [`gcsfuse`](https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/overview)
or `sudo`, and might fail due to insufficient permissions.

One alternative is to execute these binaries as the root user and
then use the `su` command to switch to another user at runtime.

For example, in your Dockerfile, remove the `USER` instruction, and in your
entrypoint script, use the following sequence:

    gcsfuse ...                 # Run gcsfuse as root
    su myuser -c "/yourapp.sh"  # Switch to 'myuser' and run 'yourapp.sh'

### Executing user

If the [user name](https://docs.docker.com/reference/dockerfile/#user) doesn't
exist, Cloud Run runs the container as the root user (`uid=0`).

## Communication between containers of the same instance

Cloud Run adds an entry to the `/etc/hosts` file in each
container. This entry maps the service names to the localhost IP address
(`127.0.0.1`). This lets containers communicate with each other using their
container name.

## Instance metadata server

Cloud Run instances expose a metadata server that you can use
to retrieve details about your containers, such as the project ID,
region, instance ID or service accounts. You can also use the metadata server to
[generate tokens for the service identity](https://docs.cloud.google.com/run/docs/securing/service-identity).

To access metadata server data, use HTTP requests to the
`http://metadata.google.internal/` endpoint with the `Metadata-Flavor: Google`
header: no client libraries are required. For more information, see
[Getting metadata](https://docs.cloud.google.com/compute/docs/storing-retrieving-metadata#querying).

The following table lists some of the [available metadata](https://docs.cloud.google.com/compute/docs/metadata/predefined-metadata-keys) server information:

| Path | Description |
|---|---|
| `/computeMetadata/v1/project/project-id` | Project ID of the project the Cloud Run resource belongs to. |
| `/computeMetadata/v1/project/numeric-project-id` | Project number of the project the Cloud Run resource belongs to. |
| `/computeMetadata/v1/instance/region` | Region of this Cloud Run resource, returns `projects/PROJECT-NUMBER/regions/REGION` |
| `/computeMetadata/v1/instance/id` | Unique identifier of the instance (also available in [logs](https://docs.cloud.google.com/run/docs/logging)). |
| `/computeMetadata/v1/instance/service-accounts/default/email` | Email for the service identity of this Cloud Run resource. |
| `/computeMetadata/v1/instance/service-accounts/default/token` | Generates an OAuth2 access token for the [service account of this Cloud Run resource](https://docs.cloud.google.com/run/docs/securing/service-identity). The Cloud Run [service agent](https://docs.cloud.google.com/iam/docs/service-agents) is used to fetch a token. This endpoint will return a JSON response with an `access_token` attribute. [Read more](https://docs.cloud.google.com/compute/docs/access/authenticate-workloads#applications) about how to extract and use this access token. |
| `/computeMetadata/v1/instance/network-interfaces/0/ip` | IPv4 address of a worker pool instance on a VPC network. |
| `/computeMetadata/v1/instance/network-interfaces/0/ipv6` | IPv6 address of a worker pool instance. Make sure you create your instance under a [dual-stack subnet](https://docs.cloud.google.com/run/docs/configuring/vpc-dual-stack-subnet). |
| `/computeMetadata/v1/instance/network-interfaces/` `/computeMetadata/v1/instance/network-interfaces/0/` | Network interface directory path for worker pools. |

Cloud Run doesn't provide details about which
[Google Cloud zone](https://docs.cloud.google.com/compute/docs/regions-zones) the instances
are running in. As a consequence, the metadata attribute `/computeMetadata/v1/instance/zone`
always returns `projects/PROJECT-NUMBER/zones/REGION-1`.

## File names

The file names that you use in containers must be UTF-8 compatible, either UTF-8
or something that can be safely auto-converted to UTF-8. If your file names use
different encodings, run Docker build on a machine with UTF-8 compatible filenames,
and avoid copying files to a container that contains incompatible UTF-8 names.

Container deployment fails if file names are not UTF-8 compatible. Note that
there's no restriction on the character
encoding you use within a file.

## Outbound request timeouts

For Cloud Run services and jobs, there is a timeout after
10 minutes of idle time for requests from your container to
[VPC](https://docs.cloud.google.com/run/docs/configuring/connecting-vpc).
For requests from your container to the internet, there is a timeout after
20 minutes of idle time.

## Outbound connection resets

Connection streams from your container to both [VPC](https://docs.cloud.google.com/run/docs/configuring/connecting-vpc) and internet can be
occasionally terminated and replaced when underlying infrastructure is restarted
or updated. If your application reuses long-lived connections, we
recommend that you configure your application to re-establish connections to
avoid the reuse of a dead connection.