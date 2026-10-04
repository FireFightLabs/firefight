---
name: axiom_errors
when: Finding why a service whose traces or logs go to Axiom returns errors or fails requests
tools: [search_errors, search_traces, search_logs, querydataset]
references: [sre/query-patterns.md, sre/apl.md, sre/apl-operators.md, sre/failure-modes.md]
---
1. Call `search_errors` for the service over a range that starts well before the errors. It groups the failed spans by operation and status message, with when each was first and last seen, so a kind of error that began with the problem stands out.
2. Count the errors over time with `querydataset`, on the traces dataset, where service.name is the service and error is true, summarized by count over bin_auto(_time) and name. A rise that begins at one minute points at a change at that minute.
3. Call `search_traces` for the failed requests, then `querydataset` with where trace_id equals one of them to read every span of that trace. The failing span names the call that broke, such as a database or another service.
4. Call `search_logs` with the error's text for the lines around it, which often carry the exception.
