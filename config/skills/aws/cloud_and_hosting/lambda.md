---
name: aws_lambda
when: Finding why a Lambda function errors, times out, runs out of memory or is throttled, and moving its alias back to an earlier version
tools: [resource_status, query_metrics, cloudwatch_metrics, search_logs, logs_insights_query, recent_deploys, rollback]
references: [serverless/troubleshooting.md, serverless/concurrency.md, serverless/lambda.md, lambda-timeouts/lambda-timeout-debugging.md]
---
1. Call `resource_status`. A state of Failed, or a last update that failed, means the function cannot run as it is, and the reason says why. Note its memory, timeout, whether it runs in a VPC, and which version each alias points at.
2. Call `query_metrics` over the window with `metrics` errors and requests, which are the function's Errors and Invocations. Errors counts invocations that ended in a function error, which includes timeouts and errors the runtime raised. Divide Errors by Invocations for the error rate. `cloudwatch_metrics` reads Duration, Throttles and ConcurrentExecutions too.
3. Match the cause:
   - Timeouts: Duration near the timeout. A timed out invocation writes Status: timeout on its REPORT line, and Task timed out in the older log format. Search for them with `search_logs` and `text`. A function in a VPC that calls the internet needs a NAT gateway, and a call that hangs until the timeout is often that.
   - Out of memory: run `logs_insights_query` on the function's log group with filter @type = "REPORT" | filter @maxMemoryUsed / @memorySize > 0.9 to find invocations near their memory.
   - Throttling: Throttles above zero, with ConcurrentExecutions at the function's reserved concurrency or the account's limit in the region. A reserved concurrency of 0 throttles every call. A throttled synchronous call returns 429 to its caller, and an asynchronous one is retried.
   - Errors from the code: read the error lines with `search_logs` and `text` set to the error's words.
4. Call `recent_deploys`. A version published shortly before the errors began is the first suspect. Lambda moves traffic between versions through an alias, so a function no caller reaches through an alias has nothing to roll back.
5. To roll back, `rollback` with `to` set to the version to go back to, or alias:version, such as live:12, when the function has more than one alias. Undo by pointing the alias back at the version it had, which the answer names.
6. When the function is defined as code, such as SAM, CDK, the Serverless Framework or Terraform, the lasting fix is a pull request to that code.
