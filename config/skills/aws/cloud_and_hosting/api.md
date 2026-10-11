---
name: aws_api
when: A question about AWS that the other AWS tools do not answer, such as a load balancer's target health, an Auto Scaling group's activities, an SQS queue's depth, a DynamoDB table, an EKS cluster, Route 53 records, a certificate's expiry, or anything else AWS's API reads, and finding out whether AWS's API offers a read at all
tools: [api_read, list_resources, run_history, build_log]
references: [api/acm/index.md, api/apigateway/index.md, api/apigatewayv2/index.md, api/apprunner/index.md, api/autoscaling/index.md, api/cloudformation/index.md, api/cloudfront/index.md, api/cloudtrail/index.md, api/cloudwatch/index.md, api/codebuild/index.md, api/codedeploy/index.md, api/codepipeline/index.md, api/dynamodb/index.md, api/ec2/index.md, api/ecr/index.md, api/ecs/index.md, api/eks/index.md, api/elasticache/index.md, api/elasticbeanstalk/index.md, api/elbv2/index.md, api/health/index.md, api/iam/index.md, api/kms/index.md, api/lambda/index.md, api/logs/index.md, api/rds/index.md, api/route53/index.md, api/s3/index.md, api/secretsmanager/index.md, api/sns/index.md, api/sqs/index.md, api/ssm/index.md, api/sts/index.md]
---
`api_read` calls one operation of one AWS service and answers what AWS said. It only reads, operations AWS names Describe, List, Get or BatchGet, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, restart and scale tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is on the map, and `run_history` and `build_log` for a CodeBuild project's builds and what each printed. Reach for `api_read` for the rest.
2. Find the operation in the service's API reference before the first call, not by guessing: read api/<service>/index.md for the service (use_skill with this skill and that reference), such as api/codepipeline/index.md, which lists every read the service offers with its input and what it answers. When the reference lists no read for the question, AWS's API does not offer one. Say so, and give the steps in the AWS console instead.
3. Set `service` to the service's name as the reference is filed under it, such as elbv2 for load balancers or logs for CloudWatch Logs, `operation` to the operation, such as ListPipelineExecutions, and `params` to its input by the member names the reference gives, such as {"pipeline_name": "deploy"}. Set `region` to one of this connection's regions. A global service such as IAM, Route 53 or CloudFront reads the same from any of them.
4. A list answers one page. To read on, pass the next token it answered in `params`, under the member the reference names for it, such as next_token. Narrow a list with its filters instead of reading every page.
5. Reads that answer a credential or a secret's value are never made: a Secrets Manager secret's value, a Parameter Store value, an STS token, a registry password, an instance's password. Environment variables, user data and download links come back hidden. Say which name to check in the console when the question needs a value.
6. A refusal that says the keys' policy does not allow the operation is the workspace's to fix in IAM. Name the action AWS's refusal gives, such as codepipeline:ListPipelineExecutions.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- sts: GetCallerIdentity: Which account and role the connection reads as.
- cloudtrail: DescribeTrails: Trails and the log group or bucket each writes the audit log to.
- health: DescribeEvents (filter, max_results, next_token): AWS's own outages and scheduled changes that touch the account.
- cloudwatch: DescribeAlarms (state_value, alarm_name_prefix, alarm_types, max_records, next_token): CloudWatch alarms with their state, filtered to those firing.
- cloudwatch: DescribeAlarmHistory (alarm_name, history_item_type, start_date, end_date, scan_by, next_token): When each alarm changed state and why, between two times.
- cloudwatch: GetMetricData (metric_data_queries, start_time, end_time, next_token): A metric's values over a time range, such as CPU or errors.
- logs: DescribeLogGroups (log_group_name_prefix, log_group_name_pattern, limit, next_token): The account's log groups, by name prefix, with their retention.
- logs: DescribeLogStreams (log_group_name, log_stream_name_prefix, order_by, descending, limit, next_token): A log group's streams, the most recently written first.
- logs: GetLogEvents (log_group_name, log_stream_name, start_time, end_time, start_from_head, limit, next_token): Log lines from one stream between two times, newest last.
- ecs: ListClusters (next_token, max_results): The ECS clusters in the region.
- ecs: ListServices (cluster, max_results, next_token): The services running in one ECS cluster.
- ecs: DescribeServices (cluster, services): Services with their deployments, task counts and recent events.
- ecs: ListTasks (cluster, service_name, desired_status, max_results, next_token): A cluster's tasks, running or stopped, for one service.
- ecs: DescribeTasks (cluster, tasks): Tasks with their status, stop reason and container exit codes.
- ecs: DescribeTaskDefinition (task_definition): A task definition with its image, CPU and memory.
- lambda: ListFunctions (marker, max_items): Lambda functions with their runtime and last change.
- lambda: GetFunction (function_name): One function's configuration, state and last update status.
- ec2: DescribeInstances (instance_ids, filters, max_results, next_token): EC2 instances with their state, type and addresses.
- ec2: DescribeInstanceStatus (instance_ids, filters, include_all_instances, max_results, next_token): Instance and system status checks, and scheduled maintenance events.
- elbv2: DescribeLoadBalancers (load_balancer_arns, names, page_size, marker): Load balancers with their state and DNS name.
- elbv2: DescribeTargetGroups (load_balancer_arn, target_group_arns, names, page_size, marker): Target groups with their health check settings, for one load balancer.
- elbv2: DescribeTargetHealth (target_group_arn): Whether each target in a target group is healthy, and why not.
- autoscaling: DescribeAutoScalingGroups (auto_scaling_group_names, filters, max_records, next_token): Auto Scaling groups with their sizes and instances.
- autoscaling: DescribeScalingActivities (auto_scaling_group_name, max_records, next_token): When a group scaled in or out and why, newest first.
- rds: DescribeDBInstances (db_instance_identifier, filters, max_records, marker): RDS instances with their status, class, version and endpoint.
- rds: DescribeDBSnapshots (db_instance_identifier, snapshot_type, max_records, marker): Database snapshots with when each was taken and its status.
- rds: DescribeEvents (source_identifier, source_type, start_time, end_time, event_categories, max_records, marker): RDS events such as failovers and reboots, between two times.
- eks: DescribeCluster (name): One EKS cluster with its version, status and endpoint.
- codepipeline: GetPipelineState (name): Each stage of a pipeline and the state of its latest run.
- codepipeline: ListPipelineExecutions (pipeline_name, max_results, filter, next_token): A pipeline's runs with their status and commit, newest first.
- codebuild: ListBuildsForProject (project_name, next_token): A CodeBuild project's build ids, newest first.
- codebuild: BatchGetBuilds (ids): Builds with their status, phases, commit and where their logs are.
- codedeploy: ListDeployments (application_name, deployment_group_name, include_only_statuses, create_time_range, next_token): CodeDeploy deployments for an application and group, between two times.
- cloudformation: DescribeStackEvents (stack_name, next_token): A stack's events, newest first, with each resource's status and reason.
- route53: ListHostedZones (marker, max_items): The account's Route 53 hosted zones.
- route53: ListResourceRecordSets (hosted_zone_id, start_record_name, start_record_type, max_items): The DNS records in one hosted zone.
- acm: ListCertificates (certificate_statuses, sort_by, sort_order, max_items, next_token): Certificates with their domain, status and expiry.
- iam: ListAccessKeys (user_name, marker, max_items): A user's access keys with their status and when each was made, never the secret.
- secretsmanager: ListSecrets (filters, max_results, next_token): Secrets by name and when each rotated, never their values.
- ssm: DescribeParameters (parameter_filters, max_results, next_token): Parameter Store parameters by name, never their values.
