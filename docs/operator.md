# Operator console

`/operator` is for the people who run a Firefight install, not for a workspace. It holds the overview, the incident process, workflows, the jobs dashboard, and Halon's runs, health, traces and chats. Its pages share `OperatorLayout` (`pages/operator/components/`), a layout with no workspace selector, since an operator sees all workspaces. `/operator` opens on the overview.

## Boundary

The console is self-contained, so it can be replaced or removed without changing app code.

- **Everything is under `Operator`**: controllers in `app/controllers/operator/`, models in `app/models/operator/` (including `Operator::Credential` and `Operator::WorkflowRuns`), serializers in `app/serializers/operator/`, pages in `app/frontend/pages/operator/`.
- **The app never references it.** ArchSpec (`Archspec.rb`) makes the operator files their own components, lets only them name `Operator`, and forbids every other component from using them. The same layer rules as the app's controllers, models and serializers apply to them.
- **Dependencies point one way.** The console reads app models, the ability ledger and the SolidWorkflow tables. `User` has no association to the credential, and the database deletes a user's credential with the user.
- **Shared files hold one line each**: the route block in `config/routes.rb`, the Flightdeck base controller in `config/initializers/flightdeck.rb`, and `Operator::TypescriptConstants.exports` in `lib/typescript_constants.rb`.
- **What the app records for everyone** and the console reads: `PlatformCallFailure`, `investigations.answer_posted_at`, `inferences.prompt_version`. They name nothing in the console.
- **Actions have one guard each** in `Operator::Actions`, a sentence saying why not or nil. Controllers refuse with it and serializers ship it, so a page shows a button only when the server would accept it.

## Who gets in

- **An operator is a user id in `OPERATOR_USER_IDS`**, comma separated, read on every request (`Operator::Credential.operator?`). It is deploy config, so nothing a workspace can edit makes someone an operator. A user id rather than an email, since an email is only as good as whichever sign-in method last vouched for it.
- **Anyone else gets the app's own not found page**, signed in or not, on every console address including the jobs dashboard (`Operator::BaseController#require_operator!`). The console does not reveal it exists. Flightdeck serves its own stylesheet, script and fonts without a check, by design, so an asset address can show that it is mounted, and nothing more.
- **Then an authenticator code**, asked for again every `Operator::Credential::VERIFIED_FOR` (12 hours) in a session, so a taken-over sign-in alone opens nothing. Any TOTP app works.

## The second factor

`Operator::Credential` (table `operator_credentials`), one row per operator:

- **Setup** at `/operator/setup` shows a QR code (drawn by the page from the squares `rqrcode` returns, so no markup crosses to the browser) and the key in groups of four. The secret is created once and kept until the first code confirms it, so a mistyped code does not mean scanning again. It is encrypted.
- **Recovery codes**: ten, each working once, handed back once when setup is confirmed and rendered rather than redirected with, so they sit in no address, flash or log. Only an HMAC of each is stored.
- **A code works once.** The step it belongs to is claimed with one guarded `update_all`, so the same code cannot open two sessions, even from two requests at once. A code from the step before is taken, for clock drift.
- **Five wrong answers lock the factor for 15 minutes**, counted on the row so the lock holds across every process. A lock that has run out starts the count again. Rails' `rate_limit` is not used, since its count lives in the cache, which is off in tests and can be split per process.
- **After a correct code** the browser loads the next screen whole (`inertia_location`), since Flightdeck is not an Inertia page.
- **A lost phone and lost recovery codes**: `bin/rails 'operator:reset_authenticator[USER_ID]'` removes the row, and the next visit sets up anew.

## Find

The box at the top of the sidebar takes anything with an id (`Operator::Finder`): an incident, a Halon run or chat, or a workflow, and the records inside them that lead back to one (a saved chat, a model call from the inference ledger or a chat's usage row, a tool call's step or its ledger entry, a chat message, a webhook delivery). The start of an id works from 6 characters, so an id cut short in a log still finds its record. A trace row's key, as the `span` in a trace's address shows it (`model-<id>`), opens that trace at that row. An incident number such as `INC-042` is matched in every workspace, since each counts its own. One match opens the record, and several are listed with where each lives and which id found it. Matching casts each table's id to text through Arel (`Finder.id_starts`), which `WorkflowRuns.starting_with` shares for the engine's table.

## Window and workspace

The overview, Halon and chats read one window (the last 24 hours, 7 days or 30 days) across every workspace or one, from the query string (`Operator::Filter`). The window is open ended, so nothing written while the page loads is missed. The last day is charted by the hour, anything longer by the day. Figures that are not per workspace, the job queue, say so.

## Overview

`/operator` puts what needs a person first, then each process in numbers.

- **Needs attention** (`Operator::Attention`) is failures in the window and anything backed up or stuck now: failed and stuck workflows, failing webhook deliveries (one item per webhook), failed Slack calls (one item per workspace, call, error and channel, with a count), alerts stuck in routing, backed up queues and failed jobs, and Halon runs that failed on our side, reached their budget or turn limit, finished without their last post reaching the thread, or have no worker. Failures sort before warnings. Each item names what it opens (`TARGET_*`), and the serializer turns that into an address, so the model holds no routes. The nav shows the count for the last day on every console page.
- **Panels** (`Operator::Overview`) count incidents, workflows, jobs and Halon for the window.
- **The job queue** is read by `Operator::JobHealth` from Solid Queue's own tables. It returns nil when they are not there, as in tests, so the page says the queue could not be read rather than failing. It checks the table exists before querying, since a failed query would abort the transaction a caller is in.

## Halon

- **Runs and health** at `/operator/halon` (`Operator::HalonHealth`): runs and chat turns, how many answered, median and p90 time, spend from the inference ledger (runs, their citation re-read and chat turns), and the team's verdicts. A chart of runs by how they ended, and why the rest did not answer. Tools from the invocation ledger, with failed and denied calls and median time. Model calls with their error classes. The run prompt's latest wordings, each with how the runs it started went, over all time so an older wording is there to compare, and its text. Then the runs, filtered by how they ended. Rehearsals are never counted.
- **How a run ended** (`Operator::HalonRuns`): answered, stopped (a limit it reached, said to the thread in `PLAIN_STOP_REASONS`, or a person), failed (anything else, a cause on our side), or working. A failure is shown with the technical cause in `error_summary`, which only operators see.
- **A run's trace** at `/operator/halon/runs/:id` (`Operator::RunTrace`) draws every record the run left on one clock: the job claiming it, the facts it started from, each model call (from the inference ledger, placed by its latency, with its reply), each tool call (with the gateway's decision, who it ran as, its scope, time and ledger id), theories, the critique, the answer or why it stopped, the thread opening and the last post (or that it was not posted), failed Slack calls in its channel, and verdicts, which come later and do not stretch the clock. A legend says a bar took time and a diamond is a moment, and what each colour means, and hovering a mark gives when it started and how long it took. The gateway ledgers every call that leaves Firefight and every refusal, but not a read of Firefight's own data, and a refused call never reaches the step that would hold its row, so a step without a ledger row is named by what it was (a read of our own data, denied, or replayed when the run is a replay).
- **Chats** at `/operator/halon/chats`, and one chat's trace (`Operator::ChatTrace`), each turn on its own clock from what the person asked. A chat's ledger rows name its incident rather than the chat, so its model calls come from RubyLLM's usage rows and its tool calls from its saved tool calls. A tool result is saved as the tool starts and filled in when it answers, so a tool call runs from the result's `created_at` to its `updated_at`, and a model call starts when the message before it was last written. The latest 20 turns are drawn.
- **Span content is read one span at a time.** The trace carries no tool output, model reply or question, only whether a span has one. Opening a span asks for the optional `spanBody` prop with `span` in the query string, so the address says which span is open. Content past 100,000 characters is cut and says so. It is the customer's data, and the page says so beside it.

## Jobs

Flightdeck (`solid_queue-flightdeck`) is mounted at `/operator/jobs`, with `Operator::FlightdeckController` as its base controller, so every one of its pages runs both checks above. It reads Solid Queue's own tables. The test database has none, so tests prove the checks and not Flightdeck's pages.

## Incidents

`/operator/incidents` lists every incident across workspaces, newest first, with how many of its records failed (`Operator::IncidentProcess.problem_counts`: failed workflow steps, failed webhook deliveries and failed platform calls in its channel). One incident opens its whole process on one timeline, built by `Operator::IncidentProcess` from every table that records it: alerts and their routing, incident events, each workflow and its steps, webhook deliveries, failed platform calls in the incident's channel, and Halon's runs. It is read only. A failed step offers **Run again** and **Skip** (skipping asks first), and a failed delivery offers **Send again** (`WebhookDelivery#replay!`, a delivery of its own with the bytes sent the first time). The raw cause of a failure is folded under each record, and a Halon run opens its trace.

## Workflows

`/operator/workflows` lists every SolidWorkflow run, filtered by state and kind. The console reads the engine's records through `Operator::WorkflowRuns`, and ArchSpec allows only workflows, the engine and the console to name `SolidWorkflow`. One run shows its steps drawn from `depends_on` (`Operator::WorkflowGraph` puts a step one column after the last step it waits for), the selected step's attempts, time and last error, and every event the engine recorded. **Pause**, **Resume** and **Cancel** (which asks first) call the engine's own `pause!`, `resume!` and `cancel!`, and **Run again** and **Skip** its `retry_now!` and `skip!`, which bring a failed workflow back to running. Each is recorded on the workflow under the operator's email. The engine's `pause!` and `resume!` return nothing meaningful, so the state they leave is what the toast reports. Every action button is disabled while its request runs, so a double click does not act twice.

## Failed platform calls

`PlatformCallFailure` keeps every Slack API call that failed, written in `Slack::Client.noting_failure` around `api_get` and `api_post`, so every caller is covered and none can forget, and the client decides which answers are worth keeping. It keeps the endpoint, the error class and message, and the channel when the call named one, which is how an incident's timeline finds its own. Answers the app expects and handles itself (already in the channel, a channel name taken, already archived or not archived) are not kept. Recording can never break the call it records. Rows are kept for 30 days (`PlatformCallFailureCleanupJob`, daily).

