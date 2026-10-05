---
name: render_crashes
when: Instances of a service on Render crash, restart, run out of memory, or the service was suspended for crash looping
tools: [list_events, query_metrics, search_logs, resource_status, recent_deploys]
references: [debug/error-patterns.md, debug/metrics-debugging.md, monitor/metrics-guide.md]
---
Render says why an instance stopped in its events, which is more reliable than matching log text.

1. Call `list_events` for the window and read each server failed event:
   - ran out of memory, with the memory limit: the process used more than its plan allows. Load is not always the cause, so compare with step 2.
   - exited with a code: the process ended on its own. A service other than a cron job should only exit when Render asks it to stop. Code 137 means it was killed, usually for memory.
   - exited without being asked to stop: the start command returned, often a script that starts the server in the background and ends.
   - failed its health check: a running instance that fails its check for 15 seconds stops getting traffic, and after 60 seconds Render restarts it. Server restarted events follow.
   - evicted, or server hardware failure: Render moved the instance. This is Render's side, not the code.
2. Call `query_metrics` with `metrics` cpu and memory over a window that starts before the first failure. Memory climbing steadily to the limit points at a leak, and a sudden jump points at one request or job loading too much. Each instance is its own series.
3. Call `recent_deploys`. Failures that began with a deploy point at that change, and the render_fixes skill can roll it back.
4. Read the last lines before a failure with `search_logs`, `stream` app, ending at the failure's time, for the stack trace or error.
5. A service suspended by stuck_crashlooping stays down until someone resumes it in Render, after the cause is fixed. Say so.
6. More memory is a plan change made in Render's dashboard by a person. Halon cannot change a plan. A leak is a code fix. A restart buys time only until memory fills again.
