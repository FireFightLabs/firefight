---
name: vercel_triage
when: Starting on anything wrong with a site or app on Vercel, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, deployment_logs, search_logs]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact project name. It shows the state of each project's production deployment and whether the project is paused. A paused project serves DEPLOYMENT_PAUSED to every visitor until someone resumes it in Vercel.
2. Call `resource_status` on the project. Note the production deployment, its state (ready, error, building, canceled), its Git repository and production branch, and its domains. When it names a last rollback, new deployments are not going live on their own, which explains a fix that was merged but never reached production.
3. Call `recent_deploys`. A production deployment shortly before the trouble began is the first suspect, so load the vercel_fixes skill. A deployment in the error state never went live, and the one before it is still serving, so load the vercel_build_failures skill to see why it failed.
4. When visitors see an error page or a 5xx, read what the functions log with `search_logs` (`stream` app). Vercel only streams runtime logs live, so this shows what happens while it watches, and the answer says how far back the project's Logs page keeps lines. Load the vercel_function_errors skill when the lines name an error code such as FUNCTION_INVOCATION_FAILED or FUNCTION_INVOCATION_TIMEOUT.
5. To read one deployment by its id, such as one that failed, call `deployment_logs` with `deployment` and `type` build for its build or runtime for what it logs now.

Vercel's API has no metrics, restart or scaling. Functions scale on their own, so load and traffic are read on the project's Observability page in Vercel. Say so rather than guessing a number.
