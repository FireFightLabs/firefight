---
name: newrelic_nrql
when: Asking New Relic something its other tools do not answer, by writing an NRQL query
tools: [execute_nrql_query, list_available_new_relic_accounts, convert_time_period_to_epoch_ms]
references: [nrql/SKILL.md, nrql/queries.md]
---
1. `execute_nrql_query` needs the account to run in. Call `list_available_new_relic_accounts` only when you do not already know it, since it can list hundreds.
2. Check what the account holds before filtering on it. SHOW EVENT TYPES lists the event types, and SELECT keyset() FROM an event type lists its attributes. Transaction and TransactionError come from APM agents, Span from distributed tracing, Log from logs, and Deployment and ChangeTrackingEvent from change tracking.
3. Write the query with these rules in mind:
   - Strings are in single quotes, and attribute and event type names are case sensitive.
   - Every query states SINCE. Without it New Relic reads only the last hour. Time units are spelled out, such as 30 minutes ago, never 30m.
   - A FACET returns 10 groups unless LIMIT says more, up to 5000. A raw SELECT returns 100 rows unless LIMIT says more.
   - TIMESERIES gives at most 366 buckets, so a week reads well at TIMESERIES 1 hour.
   - LIKE matches with %, and RLIKE takes an RE2 expression that has to match the whole value.
4. Call `convert_time_period_to_epoch_ms` when the range is a phrase such as yesterday at 3pm, and put the result in SINCE and UNTIL.
5. A query that returns nothing proves only that nothing matched. A misspelled attribute or event type returns nothing too, so check with SELECT count(*) and no WHERE before saying the data is not there.
