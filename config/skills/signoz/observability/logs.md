---
name: signoz_logs
when: Reading, filtering or counting the logs a service sends to SigNoz
tools: [search_logs, signoz_search_logs, signoz_aggregate_logs, signoz_get_field_keys, signoz_get_field_values]
references: [queries/SKILL.md]
---
1. Call `search_logs` for the service with the text you are after. It searches the log body for that text, word for word, newest first.
2. Count before you read. Call `signoz_aggregate_logs` with aggregation count, the service, grouped by severity_text, as a time_series, to see when errors began.
3. To filter on a field, find it first with `signoz_get_field_keys` for logs, and its values with `signoz_get_field_values`. Field names differ between teams, and a filter on a field that does not exist fails.
4. Write the filter for `signoz_search_logs` in SigNoz's expression syntax, such as severity_text IN ('ERROR', 'FATAL') AND body CONTAINS 'timeout'. Quote text in single quotes, with a backslash before an apostrophe inside it.
5. A log without service.name is not found by service. When a search by service finds nothing, look for the field the team uses instead before saying there are no logs.
