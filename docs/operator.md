# Operator console

`/operator` is for the people who run a Firefight install, not for a workspace. It holds the incident process, workflows and the jobs dashboard, and Halon's screens as they land. Its pages share `OperatorLayout` (`pages/operator/components/`), a frame of its own with no workspace, since an operator looks across all of them. `/operator` opens on Incidents.

## Who gets in

- **An operator is a user id in `OPERATOR_USER_IDS`**, comma separated, read on every request (`OperatorCredential.operator?`). It is deploy config, so nothing a workspace can edit makes someone an operator. A user id rather than an email, since an email is only as good as whichever sign-in method last vouched for it.
- **Anyone else gets the app's own not found page**, signed in or not, on every console address including the jobs dashboard (`Operator::BaseController#require_operator!`). The console does not reveal it exists. Flightdeck serves its own stylesheet, script and fonts without a check, by design, so an asset address can show that it is mounted, and nothing more.
- **Then an authenticator code**, asked for again every `OperatorCredential::VERIFIED_FOR` (12 hours) in a session, so a taken-over sign-in alone opens nothing. Any TOTP app works.

## The second factor

`OperatorCredential`, one row per operator:

- **Setup** at `/operator/setup` shows a QR code (drawn by the page from the squares `rqrcode` returns, so no markup crosses to the browser) and the key in groups of four. The secret is created once and kept until the first code confirms it, so a mistyped code does not mean scanning again. It is encrypted.
- **Recovery codes**: ten, each working once, handed back once when setup is confirmed and rendered rather than redirected with, so they sit in no address, flash or log. Only an HMAC of each is stored.
- **A code works once.** The step it belongs to is claimed with one guarded `update_all`, so the same code cannot open two sessions, even from two requests at once. A code from the step before is taken, for clock drift.
- **Five wrong answers lock the factor for 15 minutes**, counted on the row so the lock holds across every process. A lock that has run out starts the count again. Rails' `rate_limit` is not used, since its count lives in the cache, which is off in tests and can be split per process.
- **After a correct code** the browser loads the next screen whole (`inertia_location`), since Flightdeck is not an Inertia page.
- **A lost phone and lost recovery codes**: `bin/rails 'operator:reset_authenticator[USER_ID]'` removes the row, and the next visit sets up anew.

## Jobs

Flightdeck (`solid_queue-flightdeck`) is mounted at `/operator/jobs`, with `Operator::FlightdeckController` as its base controller, so every one of its pages runs both checks above. It reads Solid Queue's own tables. The test database has none, so tests prove the checks and not Flightdeck's pages.

## Incidents

`/operator/incidents` lists every incident across workspaces, newest first, with how many of its records failed (`Operator::IncidentProcess.problem_counts`: failed workflow steps, failed webhook deliveries and failed platform calls in its channel). One incident opens its whole process on one timeline, built by `Operator::IncidentProcess` from every table that records it: alerts and their routing, incident events, each workflow and its steps, webhook deliveries, failed platform calls in the incident's channel, and Halon's runs. It is read only. A failed step offers **Run again** and **Skip** (skipping asks first), and a failed delivery offers **Send again** (`WebhookDelivery#replay!`, a delivery of its own with the bytes sent the first time). The raw cause of a failure is folded under each record.

## Workflows

`/operator/workflows` lists every SolidWorkflow run, filtered by state and kind. The console reads the engine's records only through `WorkflowRuns` (`app/workflows/workflow_runs.rb`), since ArchSpec keeps the `SolidWorkflow` namespace to workflows and the engine. One run shows its steps drawn from `depends_on` (`Operator::WorkflowGraph` puts a step one column after the last step it waits for), the selected step's attempts, time and last error, and every event the engine recorded. **Pause**, **Resume** and **Cancel** (which asks first) call the engine's own `pause!`, `resume!` and `cancel!`, and **Run again** and **Skip** its `retry_now!` and `skip!`, which bring a failed workflow back to running. Each is recorded on the workflow under the operator's email. The engine's `pause!` and `resume!` return nothing meaningful, so the state they leave is what the toast reports.

## Failed platform calls

`PlatformCallFailure` keeps every Slack API call that failed, written in `Slack::Client.noting_failure` around `api_get` and `api_post`, so every caller is covered and none can forget, and the client decides which answers are worth keeping. It keeps the endpoint, the error class and message, and the channel when the call named one, which is how an incident's timeline finds its own. Answers the app expects and handles itself (already in the channel, a channel name taken, already archived or not archived) are not kept. Recording can never break the call it records. Rows are kept for 30 days (`PlatformCallFailureCleanupJob`, daily).

