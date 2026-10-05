---
name: aws_triage
when: Starting on anything wrong with an ECS service, Lambda function, EC2 instance or RDS database on AWS, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, cloudwatch_metrics, search_logs, list_tasks]
references: [application-failures/application-failure-troubleshooting.md, cloudwatch/troubleshooting.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name, with `kind` or `region` when the account is large. It lists ECS services, Lambda functions, EC2 instances and RDS databases in the regions the connection reads, each with its state and ARN. Two resources of one name are told apart by their ARN.
2. Call `resource_status` on it, and note what it says before going further:
   - An ECS service: the rollout state of its deployments (COMPLETED means it reached a steady state, IN_PROGRESS that tasks are still being replaced, FAILED that the deployment circuit breaker stopped it), running against wanted tasks, and its latest events. An event saying it was unable to place a task, is unable to consistently start tasks successfully, or that a task is unhealthy in a target group is the lead. Load the aws_ecs skill.
   - A Lambda function: its state and last update status. Failed means it cannot run, which the reason names. Load the aws_lambda skill.
   - An EC2 instance: its state and the system and instance status checks. Load the aws_ec2 skill when a check is impaired or the instance is not running.
   - An RDS database: its status, pending changes and the events of the last day. Load the aws_rds skill.
3. Call `recent_deploys` for an ECS service or a Lambda function. A deployment or a new version shortly before the trouble began is the first suspect.
4. Call `query_metrics` over the window, which reads each kind's usual CloudWatch metrics when `metrics` is left out. `cloudwatch_metrics` reads any metric AWS documents for the kind by its CloudWatch name, such as Throttles for a function or FreeStorageSpace for a database. CloudWatch records ECS and Lambda metrics every minute, and EC2 every five minutes unless detailed monitoring is on, so a short spike shows only in a narrow range. Errors that rise with invocations point at load, and errors on flat traffic point at the code or something it calls.
5. Read what it printed with `search_logs` around the moment the metrics turned. For an ECS service that keeps replacing tasks, call `list_tasks` first, since a stopped task says why it stopped.
6. When something in the answer is not clear, read the AWS guide for it. The failing application guide lists where each AWS service writes its logs.
