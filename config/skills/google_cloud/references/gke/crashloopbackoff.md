If your Pods in Google Kubernetes Engine (GKE) are stuck in a `CrashLoopBackOff`
state, it means that one or more containers are repeatedly starting and then
exiting. This behavior is likely making your apps unstable or completely
unavailable.

Use this page to diagnose and resolve the underlying causes,
which often fall into categories such as resource limitations, issues with
liveness probes, app errors, or configuration mistakes. Troubleshooting
these issues helps ensure that your apps run reliably and remain available to
your users.

This information is important for Application developers who want to
identify and fix app-level problems, such as coding errors, incorrect entry
points, configuration file issues, or problems connecting to dependencies.
Platform admins and operators can identify and address platform-related issues
like resource exhaustion (`OOMKilled`), node disruptions, or misconfigured
liveness probes. For more information about the common roles and example tasks
that we reference in Google Cloud content, see
[Common GKE user roles and tasks](https://docs.cloud.google.com/kubernetes-engine/enterprise/docs/concepts/roles-tasks).

## Understand a `CrashLoopBackOff` event

When your Pod is stuck in a `CrashLoopBackOff` state, a container within it is
repeatedly starting and crashing or exiting. This *CrashLoop* triggers
Kubernetes to attempt restarting the container by adhering to its
`restartPolicy`. With each failed restart, the *BackOff* delay before the next
attempt increases exponentially (for example, 10s, 20s, 40s), up to a maximum of
five minutes.

Although this event indicates a problem within your container, it's also a
valuable diagnostic signal. A `CrashLoopBackOff` event confirms that many
foundational steps of Pod creation, such as assignment to a node and pulling the
container image, have already completed. This knowledge lets you focus your
investigation on the container's app or configuration, rather than the cluster
infrastructure.

The `CrashLoopBackOff` state occurs because of how Kubernetes, specifically the
kubelet, handles container termination based on the Pod's
[restart policy](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy).
The cycle typically follows this pattern:

1. The container starts.
2. The container exits.
3. The kubelet observes the stopped container and restarts it according to the Pod's `restartPolicy`.
4. This cycle repeats, with the container restarted after an increasing exponential back-off delay.

The Pod's `restartPolicy` is the key to this behavior. The default policy,
`Always`, is the most common cause of this loop because it restarts a container
if it exits for *any reason* , even after a successful exit. The `OnFailure`
policy is less likely to cause a loop because it only restarts on non-zero exit
codes, and the `Never` policy avoids a restart entirely.

## Identify symptoms of a `CrashLoopBackOff` event

A Pod with the `CrashLoopBackOff` status is the primary indication of a
`CrashLoopBackOff` event.

However, you might experience some less obvious symptoms of a `CrashLoopBackOff`
event:

- Zero healthy replicas for a workload.
- A sharp decrease in healthy replicas.
- Workloads with horizontal Pod autoscaling enabled are scaling slowly or failing to scale.

If a `system` workload (for example, a logging or metrics agent) has the
`CrashLoopBackOff` status, you might also notice the following symptoms:

- Some GKE metrics aren't reported.
- Some GKE dashboards and graphs have gaps.
- Connectivity issues on Pod-level networking.

If you observe any of these less obvious symptoms, your next step should be to
confirm if a `CrashLoopBackOff` event occurred.

## Confirm a `CrashLoopBackOff` event

To confirm and investigate a `CrashLoopBackOff` event, gather evidence from
Kubernetes events and the container's app logs. These two sources provide
different, but complementary views of the problem:

- Kubernetes events confirm that a Pod is crashing.
- The container's app logs can show you why the process inside the container is failing.

To view this information, select one of the following options:

### Console

To view Kubernetes events and app logs, do the following:

1. In the Google Cloud console, go to the **Workloads** page.

   [Go to Workloads](https://console.cloud.google.com/kubernetes/workload/overview)
2. Select the workload that you want to investigate. The **Overview** or
   **Details** tab displays more information about the status of the
   workload.

3. From the **Managed Pods** section, click the name of the problematic
   Pod.

4. On the Pod details page, investigate the following:

   - To see details about Kubernetes events, go to the **Events** tab.
   - To view the container's app logs, go to the **Logs** tab. This page is where you find app-specific error messages or stack traces.

### kubectl

To view Kubernetes events and app logs, do the following:

1. View the status of all Pods running in your cluster:

       kubectl get pods

   The output is similar to the following:

       NAME       READY  STATUS             RESTARTS  AGE
       POD_NAME   0/1    CrashLoopBackOff   23        8d

   In the output, review the following columns:
   - `Ready`: review how many containers are ready. In this example, `0/1` indicates that zero out of one expected container is in a ready state. This value is a clear sign of a problem.
   - `Status`: look for Pods with a status of `CrashLoopBackOff`.
   - `Restarts`: a high value indicates that Kubernetes is repeatedly trying and failing to start the container.
2. After you identify a failing Pod, describe it to see cluster-level
   events that are related to the Pod's state:

       kubectl describe pod POD_NAME -n NAMESPACE_NAME

   Replace the following:
   - `POD_NAME`: the name of the Pod that you identified in the output of the `kubectl get` command.
   - `NAMESPACE_NAME`: the namespace of the Pod.

   The output is similar to the following:

       Containers:
       container-name:
       ...
         State:          Waiting
           Reason:       CrashLoopBackOff
         Last State:     Terminated
           Reason:       StartError
           Message:      failed to create containerd task: failed to create shim task: context deadline exceeded: unknown
           Exit Code:    128
           Started:      Thu, 01 Jan 1970 00:00:00 +0000
           Finished:     Fri, 27 Jun 2025 16:20:03 +0000
         Ready:          False
         Restart Count:  3459
       ...
       Conditions:
       Type                        Status
       PodReadyToStartContainers   True
       Initialized                 True
       Ready                       False
       ContainersReady             False
       PodScheduled                True
       ...
       Events:
       Type     Reason   Age                     From     Message
       ---     ---   ---                    ---     ---
       Warning  Failed   12m (x216 over 25h)     kubelet  Error: context deadline exceeded
       Warning  Failed   8m34s (x216 over 25h)   kubelet  Error: context deadline exceeded
       Warning  BackOff  4m24s (x3134 over 25h)  kubelet  Back-off restarting failed container container-name in pod failing-pod(11111111-2222-3333-4444-555555555555)

   In the output, review the following fields for signs of a
   `CrashLoopBackOff` event:
   - `State`: the state of the container likely shows `Waiting` with the reason `CrashLoopBackOff`.
   - `Last State`: the state of the previously terminated container. Look for a `Terminated` status and review the exit code to see if there was a crash (non-zero exit code) or an unexpected successful exit (zero exit code).
   - `Events`: actions taken by the cluster itself. Look for messages about the container being started, followed by liveness probe failures or back-off warnings like `Back-off restarting failed container`.
3. To learn more about why the Pod failed, view its app logs:

       kubectl logs POD_NAME --previous

   The `--previous` flag retrieves logs from the prior, terminated
   container, which is where you can find the specific stack trace or error
   message that reveals the cause of the crash. The current container might
   be too new to have recorded any logs.

   In the output, look for app-specific errors that would cause the process
   to exit. If you use a custom-made app, the developers who wrote it are
   best equipped to interpret these error messages. If you use a prebuilt
   app, these apps often provide their own debugging instructions.

## Use the Crashlooping Pods interactive playbook

After you confirm a `CrashLoopBackOff` event, begin troubleshooting with
the interactive playbook:

1. In the Google Cloud console, go to the **GKE Interactive Playbook -
   Crashlooping Pods** page.

   [Go to Crashlooping Pods](https://console.cloud.google.com/monitoring/dashboards/gke-troubleshooting/crashloop)
2. In the **Cluster** list, select the cluster that you want to
   troubleshoot. If you can't find your cluster, enter the name of the cluster
   in the **Filter** field.

3. In the **Namespace** list, select the namespace that you want to
   troubleshoot. If you can't find your namespace, enter the namespace in the
   **Filter** field.

4. Work through each section to help you answer the following
   questions:

   1. **Identify App Errors**: which containers are restarting?
   2. **Investigate Out Of Memory Issues**: is there a misconfiguration or an error related to the app?
   3. **Investigate Node Disruptions**: are disruptions on the node resource causing container restarts?
   4. **Investigate Liveness Probe Failures**: are liveness probes stopping your containers?
   5. **Correlate Change Events**: what happened around the time the containers started crashing?
5. Optional: To get notifications about future `CrashLoopBackOff` events,
   in the **Future Mitigation Tips** section, select **Create an Alert**.

If your problem persists after using the playbook, read the rest of the guide
for more information about resolving `CrashLoopBackOff` events.

## Resolve a `CrashLoopBackOff` event

The following sections help you resolve the most common causes of
`CrashLoopBackOff` events:

- [Resource exhaustion (OOMKilled)](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#resolve-resource-exhaustion)
- [Liveness probe failure](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#resolve-liveness-probe-failures)
- [Misconfigured app](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#resolve-app-misconfigurations)

### Resolve resource exhaustion

A `CrashLoopBackOff` event is often caused by an Out of Memory (OOM) issue. You
can confirm if this is the cause if the `kubectl describe` output shows the
following:

    Last State: Terminated
      Reason: OOMKilled

For information about how to diagnose and resolve OOM events, see
[Troubleshoot OOM events](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/oom-events).

### Resolve liveness probe failures

A
[liveness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
is a periodic health check performed by the `kubelet`. If the probe fails a
specified number of times (the default number is three), the `kubelet` restarts
the container, potentially causing a `CrashLoopBackOff` event if the probe
failures continue.

#### Confirm if a liveness probe is the cause

To confirm if liveness probe failures are triggering the `CrashLoopBackOff`
event, query your `kubelet` logs. These logs often contain explicit messages
indicating probe failures and subsequent restarts.

1. In the Google Cloud console, go to the **Logs Explorer** page.

   [Go to Logs Explorer](https://console.cloud.google.com/logs)
2. In the query pane, filter for any liveness-probe-related restarts by
   entering the following query:

       resource.type="k8s_node"
       log_id("kubelet")
       jsonPayload.MESSAGE:"failed liveness probe, will be restarted"
       resource.labels.cluster_name="CLUSTER_NAME"

   Replace `CLUSTER_NAME` with the name of your cluster.
3. Review the output. If a liveness probe failure is the cause of your
   `CrashLoopBackOff` events, the query returns log messages similar to the
   following:

       Container probe failed liveness probe, will be restarted

After you confirm that liveness probes are the cause of the `CrashLoopBackOff`
event, proceed to troubleshoot common causes:

- [Review liveness probe configuration](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#review-liveness-probe-configuration).
- [Inspect CPU and disk I/0 utilization](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#inspect-cpu-disk).
- [Address large deployments](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#address-large-deployments).
- [Address transient errors](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#address-transient-errors).
- [Address probe resource consumption](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#address-probe-resource-consumption).

#### Review liveness probe configuration

Misconfigured probes are a frequent cause of `CrashLoopBackOff` events. Check
the following settings in the manifest of your probe:

- **Verify probe type** : your probe's configuration must match how your app reports its health. For example, if your app has a health check URL (like `/healthz`), use the `httpGet` probe type. If its health is determined by running a command, use the `exec` probe type. For example, to check if a network port is open and listening, use the `tcpSocket` probe type.
- **Check probe parameters** :
  - **Path (for `httpGet` probe type)**: make sure the HTTP path is correct and that your app serves health checks on it.
  - **Port**: verify that the port configured in the probe is actually used and exposed by the app.
  - **Command (for `exec` probe type)** : make sure the command exists within the container, returns an exit code of `0` for success, and completes within the configured `timeoutSeconds` period.
  - **Timeout** : make sure that the `timeoutSeconds` value is sufficient for the app to respond, especially during startup or under load.
  - **Initial delay (`initialDelaySeconds`)**: check if the initial delay is sufficient for the app to start before probes begin.

For more information, see
[Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
in the Kubernetes documentation.

#### Inspect CPU and disk I/O utilization

Resource contention results in probe timeouts, which is a major cause of
liveness probe failures. To see if resource usage is the cause of the liveness
probe failure, try the following solutions:

- **Analyze CPU usage** : monitor the CPU utilization of the affected
  container and the node it's running on during the probe intervals. A key
  metric to track is `kubernetes.io/container/cpu/core_usage_time`. High CPU
  usage on the container or the node can prevent the app from responding to
  the probe in time.

  If container CPU starvation is causing probe failures during initialization, you can use CPU startup boost to temporarily allocate more CPU resources. For more information, see [Accelerate application startup using CPU startup boost](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/boost-application-startup).
- **Monitor disk I/O** : check disk I/O metrics for the node. You can use the
  `compute.googleapis.com/guest/disk/operation_time` metric to assess the
  amount of time spent on the disk operations, which are categorized by reads
  and writes. High disk I/O can significantly slow down container startup, app
  initialization, or overall app performance, leading to probe timeouts.

#### Address large deployments

In scenarios where a large number of Pods are deployed simultaneously (for
example, by a CI/CD tool like ArgoCD), a sudden surge of new Pods can overwhelm
cluster resources, leading to control plane resource exhaustion. This lack of
resources delays app startup and can cause liveness probes to fail repeatedly
before the apps are ready.

To resolve this issue, try the following solutions:

- **Implement staggered deployments**: implement strategies to deploy Pods in batches or over a longer period to avoid overwhelming node resources.
- **Reconfigure or scale nodes**: if staggered deployments aren't feasible, consider upgrading nodes with faster or larger disks, or Persistent Volume Claims, to better handle increased I/O demand. Ensure your cluster autoscaling is configured appropriately.
- **Wait and observe**: In some cases, if the cluster is not severely under-resourced, workloads might eventually deploy after a significant delay (sometimes 30 minutes or more).

#### Address transient errors

The app might experience temporary errors or slowdowns during startup or
initialization that cause the probe to fail initially. If the app eventually
recovers, consider increasing the values defined in the `initialDelaySeconds` or
`failureThreshold` fields in the manifest of your liveness probe.

#### Address probe resource consumption

In rare cases, the liveness probe's execution itself might consume significant
resources, which could trigger resource constraints that potentially lead to the
container being terminated due to an OOM kill. Ensure your probe commands are
lightweight. A lightweight probe is more likely to execute quickly and reliably,
giving it higher fidelity in accurately reporting your app's true health.

### Resolve app misconfigurations

App misconfigurations cause many `CrashLoopBackOff` events. To
understand why your app is stopping, the first step is to examine its exit code.
This code determines your troubleshooting path:

- Exit code `0` indicates a successful exit, which is unexpected for a long-running service and points to issues with the container's entry point or app design.
- A non-zero exit code signals an app crash, directing your focus toward configuration errors, dependency issues, or bugs in the code.

#### Find the exit code

To find the exit code of your app, do the following:

1. Describe the Pod:

       kubectl describe pod POD_NAME -n NAMESPACE_NAME

   Replace the following:
   - `POD_NAME`: the name of the problematic Pod.
   - `NAMESPACE_NAME`: the namespace of the Pod.
2. In the output, review the `Exit Code` field located under the `Last State`
   section for the relevant container. If the exit code is `0`, see
   [Troubleshoot successful exits (exit code
   0)](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#troubleshoot-successful-exits). If the exit code is a number other than
   `0`, see [Troubleshoot app crashes (non-zero exit
   code)](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events#troubleshoot-app-crashes).

#### Troubleshoot successful exits (exit code `0`)

An exit code of `0` typically means the container's process finished successfully.
Although this is the outcome that you want for a task-based Job, it can signal a
problem for a long-running controller like a Deployment, StatefulSet, or
ReplicaSet.

These controllers work to help ensure a Pod is always running, so they treat any
exit as a failure to be corrected. The `kubelet` enforces this behavior by
adhering to the Pod's `restartPolicy` (which defaults to `Always`), restarting
the container even after a successful exit. This action creates a loop, which
ultimately triggers the `CrashLoopBackOff` status.

The most common reasons for unexpected successful exits are the following:

- **Container command doesn't start a persistent process** : a container
  remains running only as long as its initial process (`command` or
  `entrypoint`) does. If this process isn't a long-running service, the
  container exits as soon as the command completes. For example, a command
  like `["/bin/bash"]` exits immediately because it has no script to run.
  To resolve this issue, ensure your container's initial process starts a
  process that runs continuously.

- **Worker app exits when a work queue is empty**: many worker apps are
  designed to check a queue for a task and exit cleanly if the queue is
  empty. To resolve this, you can either use a Job controller (which
  is designed for tasks that run to completion) or modify the app's logic
  to run as a persistent service.

- **App exits due to missing or invalid configuration**: Your app might exit
  immediately if it's missing required startup instructions, such as
  command-line arguments, environment variables, or a critical configuration
  file.

  To resolve this issue, first inspect your app's logs for specific error
  messages related to configuration loading or missing parameters. Then,
  verify the following:
  - **App arguments or environment**: ensure that all necessary command-line arguments and environment variables are correctly passed to the container as expected by your app.
  - **Configuration file presence**: confirm that any required configuration files are present at the expected paths within the container.
  - **Configuration file content**: validate the content and format of your configuration files for syntax errors, missing mandatory fields, or incorrect values.

  A common example of this issue is when an app is configured to read from a
  file mounted with a `ConfigMap` volume. If the `ConfigMap` isn't attached,
  is empty, or has misnamed keys, an app designed to exit when its
  configuration is missing might stop with an exit code of `0`. In such cases,
  verify the following settings:
  - The `ConfigMap` name in your Pod's volume definition matches its
  actual name.
  - The keys within the `ConfigMap` match what your app expects to find as
  filenames in the mounted volume.

  > [!NOTE]
  > **Note:** Although a well-designed app should exit with a non-zero error code when a mandatory configuration is missing, some apps are written to exit successfully (with code `0`) in this situation.

#### Troubleshoot app crashes (non-zero exit code)

When a container exits with a non-zero code, Kubernetes restarts it. If the
underlying issue that caused the error is persistent, the app crashes again and
the cycle repeats, culminating in a `CrashLoopBackOff` state.

The non-zero exit code is a clear signal that an error occurred within the app
itself, which directs your debugging efforts toward its internal workings and
environment. The following issues often cause this termination:

- **Configuration errors**: a non-zero exit code often points to problems with
  the app's configuration or the environment it's running in. Check your app
  for these common issues:

  - **Missing configuration file**: the app might not be able to locate or access a required configuration file.
  - **Invalid configuration**: the configuration file might contain syntax errors, incorrect values, or incompatible settings, causing the app to crash.
  - **Permissions issues**: the app could lack the necessary permissions to read or write the configuration file.
  - **Environment variables**: incorrect or missing environment variables can cause the app to malfunction or fail to start.
  - **Invalid `entrypoint` or `command`** : the command specified in the container's `entrypoint` or `command` field might be incorrect. This issue can happen with newly deployed images where the path to the executable is wrong or the file itself is not present in the container image. This misconfiguration often results in the `128` exit code.
  - **Uncontrolled image updates (`:latest` tag)** : if your workload images
    use the `:latest` tag, new Pods might pull an updated image version that
    introduces breaking changes.

    To help ensure consistency and reproducibility, always use specific,
    immutable image tags (for example, `v1.2.3`) or SHA digests (for example,
    `sha256:45b23dee08...`) in production environments. This practice helps
    ensure that the exact same image content is pulled every time.
- **Dependency issues**: your app might crash if it can't connect to the other
  services it depends on, or if it fails to authenticate or has insufficient
  permissions to access them.

  - **External service unavailable** : the app might depend on external
    services (for example, databases or APIs) that are unreachable due to
    network connectivity problems or service outages. To troubleshoot this
    issue, connect to the Pod. For more information, see
    [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
    in the Kubernetes documentation.

    After you connect to the Pod, you can run commands to check for
    access to files, databases, or to test the network. For example, you can
    use a tool like `curl` to try and reach a service's URL. This action
    helps you determine if a problem is caused by network policies, DNS, or
    the service itself.
  - **Authentication failures** : the app might be unable to authenticate
    with external services due to incorrect credentials. Inspect the
    container's logs for messages like `401 Unauthorized`
    (bad credentials) or `403 Forbidden` (insufficient permissions), which
    often indicate that the service account for the Pod lacks the
    necessary IAM roles to make external Google Cloud
    service calls.

    If you use GKE Workload Identity Federation, verify that the
    principal identifier has the permissions required for the task. For more
    information about granting IAM roles to principals by
    using GKE Workload Identity Federation, see
    [Configure authorization and principals](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#configure-authz-principals).
    You should also
    [verify that the resource usage of GKE Metadata Server hasn't exceeded its limits](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/authentication#metadata-server-crashes).
  - **Timeouts**: the app might experience timeouts when waiting for
    responses from external services, leading to crashes.

- **App-specific errors**: if configuration and external dependencies seem
  correct, the error might be within the app's code. Inspect the app logs for
  these common internal errors:

  - **Unhandled exceptions**: the app logs might contain stack traces or error messages indicating unhandled exceptions or other code-related bugs.
  - **Deadlocks or livelocks**: the app might be stuck in a deadlock, where multiple processes are waiting for each other to complete. In this scenario, the app might not exit, but it stops responding indefinitely.
  - **Port conflicts**: the app might fail to start if it attempts to bind to a port that is already in use by another process.
  - **Incompatible libraries**: the app might depend on libraries or dependencies that are missing or incompatible with the runtime environment.

  To find the root cause, inspect the container's logs for a specific error
  message or stack trace. This information helps you decide whether to fix the
  app code, adjust resource limits, or correct the environment's
  configuration. For more information about logs, see
  [About GKE logs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-logs).

## What's next

- If you can't find a solution to your problem in the documentation, see
  [Get support](https://docs.cloud.google.com/kubernetes-engine/docs/getting-support) for further help,
  including advice on the following topics:

  - Opening a support case by contacting [Cloud Customer Care](https://cloud.google.com/support-hub).
  - Getting support from the community by [asking questions on StackOverflow](http://stackoverflow.com/questions/tagged/google-kubernetes-engine) and using the `google-kubernetes-engine` tag to search for similar issues. You can also join the [`#kubernetes-engine` Slack channel](https://googlecloud-community.slack.com/messages/C0B9GKTKJ/) for more community support.
  - Opening issues or feature requests by using the [public issue tracker](https://docs.cloud.google.com/support/docs/issue-trackers).