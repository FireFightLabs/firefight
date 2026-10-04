---
name: honeycomb_errors
when: Finding why a service Honeycomb watches returns errors, throws exceptions or fails requests
tools: [search_errors, run_query, get_dataset_columns, get_trace, run_bubbleup]
references: [investigation/SKILL.md, investigation/investigation-playbooks.md, queries/query-examples.md]
---
1. Call `search_errors` for the service over a range that starts well before the errors. It counts the spans that failed by operation, so you see which endpoints fail and how often.
2. Call `run_query` with COUNT where error is true, broken down by service.name over time, to see when the errors began and whether other services fail with it. A dependency that began failing first is often the cause.
3. The full exception may sit on a log event in the trace rather than on the failed span. Find the columns with `get_dataset_columns`, then query rows where exception.type exists, with samples, to get a trace id.
4. Call `get_trace` with that trace id, showing its events, to see which call failed and the exception it raised.
5. Call `run_bubbleup` on the error query, selecting the failures, to see what they have in common, such as one version after a deploy.
