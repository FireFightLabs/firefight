---
name: modal_crashes
when: A Modal function fails, its containers crash or restart, or it runs out of memory or hits a GPU fault
tools: [app_logs, resource_status, recent_deploys, restart]
---
1. Call `app_logs` with `source` system for the window. Modal names what ended a container there: a crash on start (often an import in global scope that fails), an out of memory kill, or a heartbeat timeout.
2. A crash on start means every new container fails the same way. On a deployed app Modal keeps retrying with a growing back off rather than giving up, so traffic slows to a crawl rather than stopping. Read `app_logs` with `source` stderr around the first crash for the traceback, then call `recent_deploys`. A version that went out just before the first crash is the likely cause, so load modal_deploys.
3. An out of memory kill means the container went past the memory limit its function sets. The fix is in the code, a higher memory request or limit on the function, deployed again. Say which function and how often it happened.
4. A heartbeat timeout means the main process stopped answering Modal for minutes. Modal's guide names two causes: Python's global interpreter lock held for a long time, or a shutdown that started and never finished.
5. GPU faults show as lines starting with [gpu-health] with a level and an event type such as XID. A CRITICAL one makes Modal drain the machine and move the container, so it heals by itself. A WARN one can be a bug in the code or a library. Search for it with `text` gpu-health.
6. A function interrupted and started again on the same input can be a preemption, which Modal does now and then. It only hurts work that cannot be repeated safely.
7. When the code is fine and containers hold something that went stale, such as a rotated secret or a broken connection loaded at start, `restart` rolls the app over to fresh containers on the same version. It changes nothing else.
