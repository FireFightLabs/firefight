---
name: tinybird_ingestion
when: Data in a Tinybird data source is late, missing or wrong, rows land in quarantine, appends or Kafka ingestion fail, or a copy or populate job failed
tools: [search_logs, datasource_operations, search_errors, resource_status, jobs, run_query]
---
Every operation on a data source is recorded with its result, the rows it wrote and the rows that went to quarantine.

1. Call `resource_status` for the data source. It says how many rows and bytes it holds, how many rows are in quarantine and how its operations went in the last hour, with the latest error.
2. Read its operations with `datasource_operations` for the data source, with `failed_only` when some failed. An append with rows in quarantine succeeded for the rows that fit the schema and set the rest aside, so data looks missing without any operation failing.
3. Read the quarantined rows with `run_query` on the data source's quarantine, named after it with _quarantine at the end. Its c__error and c__error_column columns say which column did not fit and why. Tinybird keeps quarantined rows for a month, and deploying a new version of the data source recreates its quarantine, so read them before the team deploys a fix.
4. Data that stopped arriving with no failed operation was not sent. Compare the time of its latest append in `datasource_operations` with when it stopped, and look at the sender rather than Tinybird.
5. For a data source fed from Kafka, use `run_query` on tinybird.kafka_ops_log for the data source over the window. Its lag column is how many messages the consumer is behind for each partition, and rows whose msg_type is warning or error say what went wrong with the cluster, the messages or a materialized view.
6. For a copy, populate, import or sync that failed, call `jobs` with `job_type` set to it and `status` set to error. A data source fed by a materialized view writes through the view's pipe, which the operation names.

Rows in quarantine are fixed by the sender or by a change to the schema. Name the column and the error, and leave the fix to the team.
