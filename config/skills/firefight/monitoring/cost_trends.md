---
name: cost_trends
when: A scheduled check of cost, or anyone asking whether the cloud bill is growing, what grew and what the month will end at
tools: [list_notices, find_resources, get_resource, what_changed]
---
1. The facts list the skills of the connected providers that report spend under billing, and the connected providers that report none. Load each of those skills in turn and read spend through it. A provider that reports none is a gap to say, never a bill that is flat.
2. For each provider, read the spend of this month so far by day and by service, and of the two months before.
3. Project this month's total from its days so far, leaving out a one off charge such as a yearly renewal. Compare it with the months before and with the same days of last month.
4. Raise a provider whose projected month is more than 20% above last month, as high above 50% or when a single service doubled. Name what grew and since which day.
5. When a service grew, find what changed with `what_changed` for the workspace, or for the resource or `service` behind it, over the days since it grew (`minutes`): deploys, settings changed by hand, scaling and new resources, in one list. Then read what it runs on with `find_resources` and `get_resource`, such as new instances or a larger database.
6. The topic is the provider and what grew, such as the AWS bill or EC2 on AWS. The day it becomes a problem is the end of the month, or the day a budget the notes name is spent.
7. Read `list_notices` with `signal` cost first, and keep the topic of anything raised before.
8. Stopping or resizing something to save money is a change for a person to decide, never part of a check.
