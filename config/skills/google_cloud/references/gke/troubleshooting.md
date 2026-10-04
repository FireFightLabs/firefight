This document lists troubleshooting documents for common issues that you might
encounter when using Google Kubernetes Engine (GKE). Whether you're diagnosing
workload errors like `ImagePullBackOff` and `CrashLoopBackOff`, debugging
cluster autoscaling behavior, resolving PersistentVolume issues, or
troubleshooting node registration problems, the documents listed here can help.

If you're new to troubleshooting in GKE, start with
[Introduction to troubleshooting](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#introduction).

To diagnose and resolve issues you encounter, see the documents in the
following sections:

- [Cluster setup](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#cluster-setup)
- [Autoscaling](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#autoscaling)
- [Storage](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#storage)
- [Cluster security](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#cluster-security)
- [Workloads](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#workloads)
- [Cluster management](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#cluster-management)
- [Monitoring](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#monitoring)
- [4xx errors](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#gke_service_account_deleted)
- [Known issues](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting#known-issues)

To troubleshoot GKE networking, see
[Troubleshoot GKE networking](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshoot-networking)
in the GKE networking documentation.

This document is for Admins and architects, Security specialists,
Networking specialists, or Storage specialists who troubleshoot
GKE configurations. To learn more about GKE roles,
see
[Common GKE user roles and tasks](https://docs.cloud.google.com/kubernetes-engine/enterprise/docs/concepts/roles-tasks).

## Introduction to troubleshooting

| Topic | Description |
|---|---|
| [Introduction to GKE troubleshooting](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction) | Get started troubleshooting GKE by learning about the overall process and fundamental concepts. |
| [Review service health and incidents](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-service-health) | Learn how to check the health of GKE and related Google Cloud services to exclude platform issues. |
| [Assess cluster and workload health in the Google Cloud console](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-console) | Learn how to use the Google Cloud console to investigate and resolve GKE issues. |
| [Investigate a cluster's state with `kubectl`](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-kubectl) | Explore common `kubectl` commands and techniques for diagnosing problems in your clusters and workloads. |
| [Conduct historical analysis with Cloud Logging](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-logging) | Understand how to effectively use Cloud Logging to find root causes of issues in GKE. |
| [Perform proactive monitoring with Cloud Monitoring](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-monitoring) | Utilize Cloud Monitoring dashboards and metrics to identify, diagnose, and resolve GKE issues. |
| [Accelerate diagnosis with Gemini Cloud Assist](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-gemini) | Discover how Gemini can assist in diagnosing and resolving GKE problems. |
| [Put it all together: Example troubleshooting scenario](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/introduction-example) | Follow a step-by-step example of troubleshooting a common scenario in GKE. |

## Cluster setup

| Topic | Description |
|---|---|
| [Cluster creation](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/cluster-creation) | Resolve issues with creating clusters. |
| [Autopilot clusters](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/autopilot-clusters) | Diagnose and troubleshoot GKE Autopilot clusters, including cluster creation, namespace deletion, scaling, and workload issues. |
| [Kubectl command-line tool](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/kubectl) | Troubleshoot the `kubectl` command-line tool in GKE, including issues with authentication, authorization. This page also includes advice on how to [troubleshoot the Konnectivity proxy](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/kubectl#konnectivity_proxy) to check if it's causing the `kubectl logs`, `attach`, `exec`, or `port-forward` commands to stop responding. |
| [Standard node pools](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/node-pools) | Troubleshoot GKE Standard node pools, including issues with node pool creation, best-effort provisioning, corrupted instance metadata, and migrating workloads to new node pools. |
| [Node `NotReady` status](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/node-notready) | Learn how to diagnose and resolve the node `NotReady` status in GKE by troubleshooting common causes such as resource shortages, network issues, and component failures. |
| [Node registration](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/node-registration) | Troubleshoot issues that occur when adding nodes to your GKE Standard cluster, such as node registration failures and missing prerequisites for successful node registration. |
| [Container runtime](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/container-runtime) | Troubleshoot container runtimes in GKE, including issues with `containerd` and `dockershim`, and private registries. |
| [Windows Server node pools](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/windows-server-node-pools) | Troubleshoot issues with Windows Server node pools in GKE, including Pod start failures, image pull errors, network connectivity problems, and node status issues. |

## Autoscaling

| Topic | Description |
|---|---|
| [Cluster autoscaler not scaling down](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/cluster-autoscaler-scale-down) | Diagnose and resolve common reasons your cluster isn't removing underutilized nodes. Learn how to check for issues like restrictive `PodDisruptionBudgets`, Pods with local storage, or specific annotations (for example, `"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"`) that prevent node eviction. |
| [Cluster autoscaler not scaling up](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/cluster-autoscaler-scale-up) | Learn why the cluster autoscaler isn't adding new nodes to meet demand. Check for unschedulable Pods, verify that you haven't hit cluster or node pool size limits, and identify potential resource quota or regional VM availability issues. |
| [Horizontal Pod autoscaling](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/horizontal-pod-autoscaling) | Troubleshoot problems with the Horizontal Pod Autoscaler not scaling your application's Pod replicas. Resolve common issues, such as misconfigured HorizontalPodAutoscaler resources or problems with the metrics pipeline. |
| [Vertical Pod autoscaling](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/vertical-pod-autoscaling) | Troubleshoot problems with the VerticalPodAutoscaler not scaling your application's Pod resources. Resolve common issues, such as misconfigured VerticalPodAutoscaler resources or problems with the metrics pipeline. |

## Storage

| Topic | Description |
|---|---|
| [Storage](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/storage) | Troubleshoot storage, including issues with regional persistent disks, disk performance, and volume expansion. |

## Cluster security

| Topic | Description |
|---|---|
| [Authentication](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/authentication) | Troubleshoot authentication in GKE, including issues with RBAC, Workload Identity Federation for GKE, and the GKE metadata server. |
| [Service accounts](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/service-accounts) | Troubleshoot service accounts, including restoring the default service account and enabling the Compute Engine default service account. |
| [Application-layer secrets](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/troubleshoot-secrets) | Troubleshoot issues that can occur when configuring application-layer secrets encryption, including failed updates and errors [where you're unable to use a Cloud KMS key](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/troubleshoot-secrets#kms-key-error) or [where the Cloud KMS key version was destroyed](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets#what_happens_when_you_destroy_a_key). |

### Cluster's root Certificate Authority expiring soon

| Topic | Description |
|---|---|
| [Root Certificate Authority (CA) expiring](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/credential-rotation) | If your cluster's root Certificate Authority (CA) is expiring soon, learn how to perform a [credential rotation](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/credential-rotation) to prevent normal cluster operations from being interrupted. |

## Workloads

| Topic | Description |
|---|---|
| [Deployed workloads](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/deployed-workloads) | Troubleshoot errors for workloads running in a GKE cluster, including [`PodUnschedulable`](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/deployed-workloads#PodUnschedulable). Read the PodUnschedulable section for advice on errors like [`MatchNodeSelector`](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/deployed-workloads#MatchNodeSelector) and [`Does not have minimum availability`](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/deployed-workloads#minimum-availability). |
| [Image pulls](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/image-pulls) | Troubleshoot image pulls. Learn what causes statuses like [`ImagePullBackOff` and `ErrImagePull`](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/image-pulls#diagnose-image-failure) and how to resolve these statuses by fixing common issues like authentication and network connectivity. |
| [CrashLoopBackOff events](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/crashloopbackoff-events) | Troubleshoot `CrashLoopBackOff` events in GKE. Diagnose issues like resource exhaustion, app misconfigurations, and liveness probe failures. |
| [OOM events](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/oom-events) | Troubleshoot Kubernetes Out of Memory (OOM) events. Identify causes, distinguish event types, and apply effective solutions for both container- and node-level OOM kills. |
| [Arm workloads](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/arm-workloads) | Troubleshoot issues with Arm workloads, including Pods on Arm nodes crashing. |
| [TPUs](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/tpus) | Troubleshoot TPUs, including issues with quota, node auto-provisioning, workload configuration, and scheduling. |
| [GPUs](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/gpus) | Troubleshoot GPUs, including issues with GPU driver installation, device plugin errors, and container images. |

## Cluster management

| Topic | Description |
|---|---|
| [Cluster upgrades](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/upgrades) | Troubleshoot and resolve GKE cluster and node upgrade issues, including long or incomplete upgrades, unexpected auto-upgrades, failures, and post-upgrade problems. |
| [Webhooks](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/optimize-webhooks) | Understand how to troubleshoot and ensure the stability of your cluster control plane when using admission webhooks. |
| [Namespace stuck in the `Terminating` state](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/terminating-namespaces) | Troubleshoot issues with namespaces stuck in the `Terminating` state by identifying and removing the unhealthy components that are blocking deletion. |
| [Concurrent operations](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/concurrent-operations) | Troubleshoot concurrent operations by learning how to identify these errors and resolve them by waiting for operations to complete. |

## Monitoring

| Topic | Description |
|---|---|
| [System metrics](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/system-metrics) | Troubleshoot system metrics not appearing in Cloud Monitoring. |
| [Monitoring dashboards](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/dashboards) | Troubleshoot monitoring dashboards, including issues with enabling monitoring, missing Kubernetes resources, and permissions. |
| [Troubleshoot missing logs](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/logging) | Troubleshoot missing GKE logs. Learn how to check API status, cluster settings, permissions, quotas, filters, and application behavior. |

## 4xx errors

| Topic | Description |
|---|---|
| [4xx errors](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/4xx-errors) | Troubleshoot some of the 400, 401, 403, and 404 errors that you might encounter when using GKE. This page also includes information on how to troubleshoot [missing edit permissions on account errors](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/4xx-errors#gke_service_account_deleted). |

## Known issues

| Topic | Description |
|---|---|
| [Known issues](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/known-issues) | Identify and resolve known issues that might affect your use of GKE. |

## What's next

- If you can't find a solution to your problem in the documentation, see
  [Get support](https://docs.cloud.google.com/kubernetes-engine/docs/getting-support) for further help,
  including advice on the following topics:

  - Opening a support case by contacting [Cloud Customer Care](https://cloud.google.com/support-hub).
  - Getting support from the community by [asking questions on StackOverflow](http://stackoverflow.com/questions/tagged/google-kubernetes-engine) and using the `google-kubernetes-engine` tag to search for similar issues. You can also join the [`#kubernetes-engine` Slack channel](https://googlecloud-community.slack.com/messages/C0B9GKTKJ/) for more community support.
  - Opening issues or feature requests by using the [public issue tracker](https://docs.cloud.google.com/support/docs/issue-trackers).