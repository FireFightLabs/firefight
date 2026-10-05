---
name: modal_timeouts
when: A Modal function times out, runs longer than expected, or is retried more than it should be
tools: [app_logs, resource_status, recent_deploys]
---
1. Call `app_logs` with `source` system and `text` timeout for the window. A function that ran past its timeout is stopped and the caller gets a FunctionTimeoutError.
2. Modal stops a function after 300 seconds unless its code sets a timeout, anywhere from 1 second to 24 hours. The time counts only while the code runs, not while it waits to be scheduled, and it starts again on each retry, so a function with retries can run several times its timeout in all.
3. Slow starts have their own limit, the startup timeout, which covers imports, global scope and enter methods. A container that fails while loading a large model or data points there rather than at the work itself.
4. Call `recent_deploys`. A timeout that began with a new version is a change in the code or its settings. One that began on its own points at something the function calls, or at more work per input.
5. Retries are set per function. Each retry waits a second by default, and failed containers of a deployed app are started again without end, with a back off, so repeated failures show as many retries rather than one error.
6. Say which function timed out, its timeout if the logs show it, how often, and whether the cause is the code, the start or something it calls. The fix is a setting in the code, deployed again.
