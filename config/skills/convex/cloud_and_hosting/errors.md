---
name: convex_errors
when: A Convex function is throwing errors, such as a query, mutation or action failing for users
tools: [search_errors, function_errors, search_logs, recent_deploys]
references: [insights/SKILL.md]
---
1. Call `search_errors` for the window to see which functions fail, how often and with what error. A function path looks like messages:send, the file then the exported function.
2. Call `function_errors` with `function` set to the worst one, to see only its groups and whether Convex will retry them. An error raised on purpose in the app's code (a ConvexError) is usually a validation the client tripped, not an outage.
3. Call `search_logs` with `text` set to the function's path to read what it printed before it failed. Errors of a query or mutation mean the code or the data it read, errors of an action often mean a service it calls.
4. Call `recent_deploys`. If the errors began right after a push, load the convex_changes skill.
5. Say which function fails, how many times, the error in its own words, and what the logs and the timing point at.
