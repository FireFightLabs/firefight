---
name: aws_ecs
when: Finding why an ECS service fails to deploy, keeps replacing its tasks, cannot place tasks or fails its health checks, and rolling it back, restarting it or scaling it
tools: [resource_status, list_tasks, recent_deploys, search_logs, query_metrics, rollback, restart, scale]
references: [containers/ecs.md, containers/ecs-workloads.md, containers/action-logs.md, containers/ecs-managing-compute.md]
---
1. Call `resource_status`. Read the deployments, the circuit breaker line and the latest events, newest first. ECS writes an event each time it acts, and the message names the cause:
   - unable to place a task: no capacity met the task's CPU, memory, ports or constraints, or a Fargate or vCPU limit was reached. The rest of the message says which.
   - is unable to consistently start tasks successfully: tasks start and stop again. Go to step 2.
   - is unhealthy in a target group, or not healthy in a target group: the load balancer's health check fails. Compare the health check path and port with what the container serves, and the health check grace period with how long the app takes to boot.
   - deployment failed: tasks failed to start: the circuit breaker stopped the deployment, and rolled it back when it is set to.
2. Call `list_tasks`. ECS keeps stopped tasks for about an hour. The stop code and reason, and each container's exit code, say why a task stopped:
   - OutOfMemoryError, or exit code 137: a container used more memory than the task definition gives it. Confirm with `query_metrics`, `metrics` memory near the top before the stops.
   - CannotPullContainerError: the image cannot be pulled, such as a wrong tag, a deleted image, or no route to the registry.
   - ResourceInitializationError: the task could not get what it needs before starting, often a secret or parameter its execution role may not read, or no network route to fetch it.
   - Essential container in task exited: the app stopped by itself. Its last lines say why.
   - Task failed ELB health checks: the load balancer replaced it, as in step 1.
3. Read the last lines with `search_logs`, `start` a minute before a task stopped and `end` just after. The service's logs are read from the awslogs log group its task definition names.
4. Call `recent_deploys`. Trouble that began with a deployment points at that task definition revision. Its images show what changed.
5. To fix, pick the change and say how to undo it in the step:
   - Roll back, when a deployment broke it: `rollback` with `to` set to a revision of the same family from `recent_deploys`, such as web:41. ECS starts a deployment of that revision. Undo by rolling back to the revision it ran before.
   - Restart, for tasks stuck in a bad state while the code is fine: `restart` starts a new deployment of the same revision and replaces every task. Nothing to undo.
   - Scale, for load it cannot keep up with: `scale` with `instances`. Undo by scaling back to the count `resource_status` showed. An auto scaling policy on the service can change the count again.
6. When the service is defined as code, such as CloudFormation, CDK or Terraform, the fix is a pull request to that code instead, since the next deploy of it would undo a change made here.
7. A change the access key's policy refuses is the workspace's to fix in IAM. Say which action AWS named, and keep the rest of the fix.
