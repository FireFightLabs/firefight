---
name: aws_logs_insights
when: Counting, grouping or finding patterns in CloudWatch Logs, such as errors per minute, the slowest requests or which log groups hold a message, beyond the newest lines search_logs returns
tools: [logs_insights_query, search_logs, resource_status]
references: [cloudwatch/log-insights.md]
---
1. Find the log groups. `resource_status` names the log group of an ECS service's containers and of a Lambda function, and an RDS database's exported logs are under /aws/rds/instance/ followed by its name and the log type. Several groups in one region can be queried at once, in `log_groups`, with their `region`.
2. Write the query in the Logs Insights query language, commands joined with a pipe:
   - fields @timestamp, @message picks what each row shows. @timestamp, @message and @logStream are on every event, and fields in JSON logs are read by name with dots, such as req.path.
   - filter @message like "timeout" keeps events containing the text, filter @message like /time(d)? ?out/ matches a regular expression, and not like leaves out. Text matches are case sensitive unless the expression starts with (?i).
   - stats count(*) by bin(5m) counts per five minutes, and stats count(*) by field groups by a field. sort and limit order and cut the rows.
   - parse @message "user=* path=*" as user, path pulls fields out of unstructured lines.
3. Run it with `logs_insights_query`, with `minutes` or `start` and `end` around the problem. Logs Insights charges for the data it scans, so keep the range to what is needed and the log groups to the ones that matter.
4. For a Lambda function, its REPORT lines carry @duration, @billedDuration, @maxMemoryUsed, @memorySize and, on a cold start, @initDuration, so filter @type = "REPORT" | stats avg(@duration), max(@duration) by bin(5m) shows how long invocations took.
5. A query that runs past the wait is stopped, so narrow the range or filter and run it again. For the newest lines of one resource, `search_logs` is quicker.
