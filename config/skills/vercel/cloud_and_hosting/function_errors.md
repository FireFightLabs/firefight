---
name: vercel_function_errors
when: Visitors get a 5xx or an error page from a Vercel project, such as FUNCTION_INVOCATION_FAILED, FUNCTION_INVOCATION_TIMEOUT, NO_RESPONSE_FROM_FUNCTION, FUNCTION_THROTTLED or a middleware error
tools: [search_logs, deployment_logs, recent_deploys, resource_status]
---
Vercel names each failure with an error code on the error page and in the logs. Find the code first, then read what the function printed.

1. Call `search_logs` on the project (`stream` app), with `text` set to the code or a path that fails when you know one. Vercel only streams runtime logs live, so the failing request has to happen while it watches. Ask for up to a minute of watching with `deployment_logs` and `seconds` when errors are rare. Older lines are on the project's Logs page, which the answer links to.
2. Read the code:
   - FUNCTION_INVOCATION_FAILED (500): the function crashed, threw an error nothing caught, or a promise was rejected with no handler. The lines just before the error name it.
   - NO_RESPONSE_FROM_FUNCTION (502): the function ended without answering, often after an error at the top level or a deployment that broke on import.
   - FUNCTION_INVOCATION_TIMEOUT (504): the function ran past its maximum duration. It usually waits on something slow, such as a database or another API, or never sends its answer. Look for what it called last.
   - EDGE_FUNCTION_INVOCATION_FAILED and EDGE_FUNCTION_INVOCATION_TIMEOUT: the same for an edge function. A Vercel outage can cause these too, so check Vercel's status page when the code did not change.
   - MIDDLEWARE_INVOCATION_FAILED or MIDDLEWARE_INVOCATION_TIMEOUT: the middleware that runs before every request threw or took too long, so every path fails at once.
   - FUNCTION_THROTTLED (503): too many invocations at once, from a burst of traffic or a slow backend holding invocations open.
   - FUNCTION_PAYLOAD_TOO_LARGE (413) or FUNCTION_RESPONSE_PAYLOAD_TOO_LARGE: a request or response body over Vercel's limit.
3. Call `recent_deploys`. Errors that began with a production deployment point at that change, so load the vercel_fixes skill to roll it back. Errors on an unchanged deployment point at something it depends on.
4. A function that runs out of memory is stopped and fails the request. Its log lines usually say so, and the limit is set per project in Vercel.
