---
name: logfire_exceptions
when: Finding why a service that sends to Logfire raises exceptions or fails requests
tools: [search_errors, query_run, query_find_exceptions_in_file, project_logfire_link]
references: [query/SKILL.md, query/schema.md]
---
1. Call `search_errors` for the service over a range that starts well before the errors, to see each kind of exception and when it began.
2. Count them over time with `query_run`: SELECT time_bucket(interval '5 minutes', start_timestamp) AS bucket, exception_type, count(*) FROM records WHERE service_name = 'the service' AND is_exception GROUP BY bucket, exception_type ORDER BY bucket LIMIT 200. A rise that begins at one bucket points at a change at that time, such as a deploy (service_version says which).
3. Read one occurrence with `query_run`, selecting exception_message, exception_stacktrace, trace_id, span_name and http_route. The stack trace names the file and line.
4. When you know the file, `query_find_exceptions_in_file` lists the latest exceptions raised in it.
5. Read every span of that trace with `query_run` WHERE trace_id = 'the id' ORDER BY start_timestamp, to see which call failed first. `project_logfire_link` with the trace id gives its page in Logfire for your answer.
