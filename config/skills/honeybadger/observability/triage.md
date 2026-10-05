---
name: honeybadger_triage
when: Any question about the errors, uptime or scheduled jobs Honeybadger watches, such as what started failing, since when, or which deploy brought it
tools: [search_errors, resource_status, list_projects, list_faults, get_fault_counts, get_project_occurrence_counts, list_check_ins]
---
How Honeybadger is reached: `search_errors` reads the Honeybadger project named like a service on the resource map, and `resource_status` the uptime checks of a hostname on the map, or one the map says a service serves. Honeybadger's own tools reach every project by its id, from `list_projects`. Each fault and notice carries its page in Honeybadger, which goes in your answer.

1. Call `search_errors` for the service over a range that starts well before the problem, or `list_faults` with the project's id. Each fault comes with how often it happened and when last. Its search takes Honeybadger's syntax, such as -is:resolved -is:ignored environment:production class:TimeoutError, and a word it does not know as a filter is searched as text.
2. Call `get_project_occurrence_counts` with the project's id and a period of hour to see when errors rose, and `get_fault_counts` for how many faults match a search.
3. Call `resource_status` for the hostname when users say the site is down.
4. Call `list_check_ins` when a scheduled job may have stopped. A check in that is missing has not reported when it should have.
5. Then load honeybadger_errors to read one fault in depth.
