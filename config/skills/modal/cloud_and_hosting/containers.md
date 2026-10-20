---
name: modal_containers
when: A Modal container is stuck, crashing, using too much memory or holding a bad state, or a Modal app has to stop serving at once
tools: [list_containers, app_logs, stop_container, rollover_app, stop_app]
---
1. Call `list_containers` with the app to see which containers run now and when each started. A container that started long before the rest, or one that never started, is often the one in trouble.
2. Call `app_logs` with that `container` and `source` set to system to read what Modal said about it, such as an out of memory kill, a crash or a timeout, then without a source for what the code printed just before.
3. One bad container is ended with `stop_container`. Modal starts new ones as the work needs them. Without `graceful` the work it held is cancelled and runs again on other containers, so a call that keeps crashing containers will crash the next one too. With `graceful` it finishes what it holds first, which suits a container that is slow rather than broken.
4. When every container is in the same bad state, such as a stale secret or connection, `rollover_app` replaces them all on the same version instead.
5. `stop_app` stops the app for good: every container ends at once, its web endpoints and schedules stop, and it can only come back by being deployed again from its code. Use it only when the app must stop serving, such as one spending money out of control or doing harm. Say exactly that before asking, and name who deployed it.
