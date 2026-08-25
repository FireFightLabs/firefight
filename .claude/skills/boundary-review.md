---
name: boundary-review
description: Review a diff for architecture leaks ArchSpec cannot see by name. Run before opening any PR that touches app/, engines/, or app/frontend/.
---

# Boundary review

ArchSpec proves the named boundaries (which file may reference which constant). This skill catches the leaks that hide behind an allowed name: a platform's shape in a column, a permission rule inlined in a controller, business logic in an entry point. Every question below is something the V2 audit found once. Answer each against the diff, not against the codebase you remember.

## Process

1. `git diff main...HEAD --stat`, then read every changed file under `app/`, `engines/`, `lib/`, `db/migrate/`, `config/`, `app/frontend/` in full.
2. Work through the checklist. For each hit, name the file and line and say which layer the code belongs in.
3. Fix what you found, or say in the PR body exactly what you left and why. Silence reads as complete.
4. Run `bundle exec archspec check` and `bin/ci`. A green ArchSpec with hits from this list is not green.

## Platform containment

The Slack adapter is the only place that knows Slack. A second platform is a second adapter and nothing else.

- **Columns and fields.** No new column, attribute, JSON key, or serializer field named after a platform (`slack_ts`, `slack_user_id`, `team_id`, `mrkdwn`). Use Firefight's names: `message_id`, `thread_id`, `platform_user_id`, `channel_id`.
- **Shapes.** No handler, service, model, or job builds or returns a platform payload: Block Kit hashes, `{ response_action: ... }`, `private_metadata` strings, mrkdwn text. Handlers ask the adapter (`build_modal`, `form_error_response`, `form_update_response`, `ai_output_style`) and pass domain objects.
- **Contract first.** Every adapter method a caller uses is declared on `PlatformAdapter` with a `@return`. A method that exists only on `Slack::WorkspaceAdapter` is a leak even if nothing outside Slack calls it yet.
- **Prompts.** The AI engine never learns a platform's markup. Style instructions come from the adapter, results come back as plain markdown or structured data.
- **Copy.** User-facing strings under `app/` name Slack only where the person is literally in Slack. "Couldn't load that user's profile" is fine, "from Slack" is a smell outside `app/adapters/slack/`.

## Permission containment

`AbilityGateway.authorize!` is the only permission check. Config is not permission.

- **No inline role checks.** `admin_access?`, `role == ...`, `owner?` in a controller, handler, MCP tool, or job that decides whether an action may run. Declare the resource and action (`authorizes`, `authorize_as`, `authorize!`) and let the gateway answer.
- **No frontend guessing.** A page decides what to render from `currentUserCan` / `useCan(resource)`, never from `currentUserIsAdmin` (which only picks navigation and banners).
- **Vocabulary, not strings.** Resources and actions come from `Ability::Action::RESOURCE_*` / `ACTION_*`. A new resource goes into `RESOURCES`, gets a label, and is either grantable or in `ADMIN_ONLY_RESOURCES`. A permission the matrix cannot show is a permission nobody can reason about.
- **Machines never inherit.** A service key or `Agent` reaches only what it was granted. Anything that lets a machine read a human's authority is wrong.
- **Ledger.** A write from a new surface arrives with a `source` and is ledgered unless it is human incident participation.

## Entry point thinness

Slack handlers, the API, MCP, and the dashboard normalize input and call shared services. They never carry logic another entry point would need.

- **Duplicated rules.** The same guard, count, or derivation in two entry points, or in an entry point and a model (`deletion_blocked_reason` re-derived in a controller, an ingest limit living in a controller). The rule belongs on the model, the entry point asks.
- **Model writes.** `create!`/`update!` on `Incident`, `IncidentAction`, `Postmortem` outside a service or the model's own `record_change!` path. Timeline events are written with the change, never alongside it.
- **Adapter calls from entry points.** A controller or handler calling `Slack::Client` or an integrations client directly, instead of the adapter or a service.

## Layer direction

- **Models never reach up.** No service, adapter, job, or controller constant in `app/models/`. If a model needs to notify, it returns a fact and the service that called it tells someone.
- **Services coordinate, models own logic.** A new file in `app/services/` that never calls an adapter, starts a workflow, or touches another system is a model in the wrong folder.
- **Engines return, the app delivers.** `engines/firefight_ai` returns drafts, strings, and its own error classes (`FirefightAi::TransientError`, `TerminalError`). It never enqueues app jobs, posts anywhere, or names a platform. Client library exceptions stop at `FirefightAi.translating_errors`.
- **Constants live once.** No TypeScript mirror of a Ruby list. Add it to `lib/typescript_constants.rb` and run `bin/rails typescript:constants`. No raw strings for identifiers, event types, action names, or resources anywhere.

## Reach

- **Every capability has a click path.** Name how a person reaches the new thing from a cold page, including the second time (already connected, already granted). A model plus controller plus serializer with no page is not shipped.
- **N, not 1.** Where the schema allows many, the UI shows many.
- **Docs.** A change a user can see has a matching change in `../firefight-landing`, opened alongside. Say so in the PR body, or say why not.

## Report

End with one list: `file:line`, the rule it breaks, what you did about it. If the list is empty say "boundary review: nothing found" so the reader knows it ran.
