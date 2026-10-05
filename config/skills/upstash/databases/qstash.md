---
name: upstash_qstash
when: Finding why QStash messages are not delivered, are retried again and again, or end up in the dead letter queue, and why schedules do not run
tools: [search_errors, search_logs, logs_list, dlq_list, qstash_list_schedules, qstash_flow_control_get]
references: [qstash/dlq.md, qstash/callbacks.md, qstash/schedules.md, qstash/queues-and-flow-control.md, qstash/deduplication.md]
---
QStash delivers a message to its destination URL and counts it delivered when the destination answers with a 2xx status. Otherwise it retries until the message's retries run out, and the message is then failed and moved to the dead letter queue. The states a delivery log shows are CREATED, ACTIVE, RETRY, ERROR, DELIVERED, FAILED, CANCEL_REQUESTED and CANCELLED.

1. Call `search_errors` for the region's QStash over the trouble. Messages are grouped by destination and the status it answered last. One destination answering 5xx is that service failing, 401 or 403 is it refusing QStash, and no answer at all is a timeout or a destination that cannot be reached.
2. Call `search_logs` for the same QStash with `text` set to the destination for the delivery attempts, newest first, with each one's state, status and error. Retries spaced further and further apart are QStash backing off.
3. When messages are not sent at all on time, call `qstash_list_schedules` with the region for whether the schedule is paused and what its cron says, and `qstash_flow_control_get` for a rate or parallelism limit holding messages back.
4. For more than the capabilities show, such as one message's attempts, call `logs_list` or `dlq_list` with the region and service qstash.
5. Say which destination fails, since when, with what answer, and whether the destination or QStash's settings need to change. Retrying or deleting what is in the dead letter queue is for a person to decide.
