---
name: aws_cost
when: Watching or explaining what the AWS account spends, a bill that grew, or which service and resources cost more than before
tools: [cost_and_usage, list_resources, describe_resource]
signals: [cost]
---
1. Read this month by day with `cost_and_usage` and `by` day, then the months before with `by` month and `months` 3. Each request costs the account $0.01, so read once and work from the answer.
2. The last day or two are estimates that grow as AWS finishes counting, so compare whole days that are not marked estimate.
3. Find the service that grew and the day it started. Compare the same days of last month, since a month with more days costs more.
4. For compute and databases, find what runs with `list_resources` and `describe_resource`: new or larger EC2 instances, more ECS tasks, a larger RDS class or more storage, and when each changed.
5. AWS refusing the read means the keys lack ce:GetCostAndUsage. Say so, and that an admin adds it to the policy of the connection's IAM user.
