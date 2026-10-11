---
name: code
when: Reading code to learn how a system really behaves, tracing a failure to the line that raised it, reviewing a change with an operator's eye, or writing a fix
tools: [recent_deploys, what_changed, search_errors]
---
What good looks like: you know how the system really behaves because you read the code that runs, at the version that is deployed. A fix addresses the cause, is as small as it can be, comes with a test that would have caught the problem, and is easy for a person to review.

How to approach it:
1. Start from what is running. `recent_deploys` and `what_changed` say which commit a service runs and what changed before it broke. Read the code at that commit, not the latest branch. The code host's code skill, such as github_code, gitlab_code or bitbucket_code, says how: one checkout searched broadly with run_shell, code_search and ask_language_server across many files, and fetch_file for one or two you already know.
2. Follow the path the failure takes, from the entry point (a route, a job, a consumer) to where it breaks. For a failing page or endpoint, find the code that handles it and check that everything running before it, its filters and callbacks and the methods they call, is defined, before suspecting data or configuration. Read definitions and usages rather than guessing what a function does.
3. Read the libraries you depend on, at the version installed, when behaviour depends on them. library_source reads one, and its documentation is on the web. Docs describe intent, the source describes reality.
4. Connect the code to the evidence. The log line, the stack trace from `search_errors` and the metric spike should each point at a line you can name.
5. When a change touches another system's interface, such as a webhook, an API, a config format or a CI trigger, read that system's documented contract (its skill and guides, search_docs, then the web) and how it is set up now (its settings, its workflows, a recent delivery) before you design it. The brief cites both and names what you could not verify.
6. Write the fix like a careful colleague: the smallest change that fixes the cause, with a test added or adjusted, and a pull request that explains what broke, why, and how the fix was checked. The code host's fixing skill, such as github_fixing, says how a change is written and opened. A change to a pull request or an issue itself, such as closing, labelling or commenting, goes through the code host's own tool for it.
7. Review with an operator's eye: what happens under load, on timeout, during a deploy, with bad input, on retry.

What to check:
- The deployed version and what changed since the last good one.
- Error handling and retries on the failing path.
- Configuration and environment differences between where it works and where it fails.
- Migrations and the data shape the code assumes.
- The tests that exist for the path, and whether CI ran them.
- Whether what you would change is defined as code, such as Terraform, Helm or a manifest. The map says where a resource is managed in code, and the fix then goes to that code.

Trade-offs:
- A quick mitigation (a rollback, a flag, scaling) often comes before a code fix. Do both: stop the damage, then fix the cause.
- A larger refactor may be right, and it is proposed on its own, apart from the incident fix.

Done means: the pull request is open with a clear explanation, CI is green, the person who needs to review it knows, and you follow it until it merges or someone decides otherwise.

Proactive habits:
- When you find one bug, look for the same pattern elsewhere.
- Turn a lesson from an incident into a check future changes are reviewed against.
