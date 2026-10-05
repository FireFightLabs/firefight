---
name: betterstack_errors
when: Finding which errors a service raises in Better Stack's error tracking, and whether a release brought them
tools: [applications, errors, error, releases, errors_query_help, query]
---
1. Call `applications` to find the application that matches the service, then `errors` for it over the range of the problem.
2. Errors that are new, or that reoccurred inside the range, are the first suspects. Call `error` on the top ones for the stack trace, the releases that raised them and how many users they reached.
3. Call `releases` for the application. A release shortly before the errors began is the first suspect, and a GitHub connection can compare its code with the one before.
4. For counts the errors tools do not give, call `errors_query_help`, then `query`.
5. Say which errors, since when, how many, and the release they came with. Changing an error's state is for a person to ask for.
