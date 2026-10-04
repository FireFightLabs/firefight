---
name: google_cloud_cloud_run_errors
when: A Cloud Run service answers with 5xx errors, such as 500, 503 or 504, or its errors rose after a deploy
tools: [search_errors, search_logs, recent_deploys, query_metrics, resource_status, rollback]
references: [run/troubleshooting.md, run/container-contract.md, run/rollouts-rollbacks-traffic-migration.md, errors/viewing-errors.md]
---
1. Call `query_metrics` with `metrics` http_5xx and requests over a range that starts well before the problem, to see when the errors began and whether traffic changed with them.
2. Call `recent_deploys`. If a revision went out just before the errors began and now serves the traffic, it is the likeliest cause.
3. Call `search_errors` for what the code raised, most frequent first, and `search_logs` with stream requests and `text` 50 for the failing requests, which show each one's status and latency.
4. Read the status and Cloud Run's message in the app logs with `search_logs`:
   - 503 "The request failed because either the HTTP response was malformed or connection to the instance had an error": an instance ran out of memory or failed its liveness probe. Look for those messages.
   - 500 or 503 with "the container instance was found to be using too much memory and was terminated": the instance went past its memory limit. Files written to its disk count against memory too. The fix is more memory in a new revision, or finding the leak.
   - 504 "The request has been terminated because it has reached the maximum request timeout": a request ran past the service's timeout. Look for what it waited on, such as a database or an outside call.
   - 500 "The request was aborted because there was no available instance": Cloud Run could not start instances fast enough. Load google_cloud_cloud_run_capacity.
5. When a new revision brought the errors and an earlier one served without them, offer `rollback` with `to` set to that earlier revision's name from `recent_deploys`. It moves all traffic there and makes no new revision. The undo is moving the traffic back.
6. Say which revision, the error and its count, the evidence, and whether the fix is a rollback, a code change or a setting.
