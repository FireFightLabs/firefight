# AI (firefight_ai engine)

All AI features live in the `engines/firefight_ai/` engine. Read this before touching AI generation, the inference ledger, or the transcript store.

## Structure

```
engines/firefight_ai/
  lib/firefight_ai/configuration.rb                  # default_model, openai_api_key, request_timeout
  app/services/firefight_ai/
    postmortem_generator.rb                          # Incident record + narrative summary → structured postmortem draft
    postmortem_section_rewriter.rb                   # Rewrite a single postmortem section on request
    incident_summary_service.rb                      # Layered incident summaries (catchup, live summary)
    incident_responder.rb                            # @mention responses in incident channels
    milestone_extractor.rb                           # Transcript → the milestones of the investigation, as data
    schemas/postmortem.rb                            # Structured-output schema for postmortem generation
    schemas/milestones.rb                            # Structured-output schema for milestone extraction
  lib/firefight_ai/errors.rb                         # TransientError / TerminalError, the only errors that leave the engine

app/jobs/
  postmortem_generation_job.rb                       # Runs the generator while Postmortem#generation_state is "generating", delivers the result
  incident_ai_response_job.rb                        # Runs the responder for @mentions and catchups, posts the answer
  milestone_noting_job.rb                            # Runs one milestone pass from the close and cancel workflows
app/services/
  postmortem_generation_service.rb                   # Draft → Postmortem row + event + channel announcement
  milestone_noting_service.rb                        # Milestones → MILESTONE_NOTED events + the watermark
```

**The engine writes text, the app delivers it.** Engine services return plain results: `PostmortemGenerator#generate` returns a `Draft` (title, summary, markdown per section, model) and `IncidentResponder#answer_question` returns a string. Nothing under `engines/firefight_ai/` names a job queue, a channel, or a platform adapter. The app-side jobs own entitlement checks, persistence (`Postmortem.complete_generation!`), announcements through `WorkspaceAdapter`, and failure notices. Each platform describes its own markup through `PlatformAdapter#ai_output_style`, which the app passes into the responder, so the engine never learns Slack mrkdwn.

**Errors stop at the engine boundary.** Every model call runs inside `FirefightAi.translating_errors`, which maps the client library's exceptions to `FirefightAi::TransientError` (worth retrying) and `FirefightAi::TerminalError` (retrying gives the same answer). Both carry `reason`, the client error's own name, for failure messages. App jobs `retry_on` the first and `discard_on` the second and never name the client library. A rate limit is transient whatever class the library raised it under: `FirefightAi.rate_limited?` reads the response status and the message, since OpenAI's tokens per minute limit arrived as a bad request and a bad request is given up on.

## Model-agnostic by configuration

The engine calls models through `RubyLLM` — no provider-specific SDK code in services. Every provider RubyLLM supports is configured the same way: one env var per RubyLLM setting, named after it. `FirefightAi::Configuration::PROVIDER_SETTINGS` is the list (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `BEDROCK_REGION`, `VERTEXAI_SERVICE_ACCOUNT_KEY`, `OLLAMA_API_BASE`, `OPENROUTER_API_KEY`, ...). `config/initializers/firefight_ai.rb` reads them into `configuration.provider_settings` and the engine hands them to `RubyLLM.configure` untouched, so adding a provider RubyLLM gains is one entry in the list. Bedrock takes its AWS credentials from the SDK's usual environment. The wire protocol and the model registry are both RubyLLM's to decide. OpenAI gets the Responses API, since it refuses tool calls with reasoning on Chat Completions, which is every call the agent makes. Model lookups read the `ruby_llm_models` table, which `RubyLLM.models.refresh` fills from the published catalog, so a model the gem does not know can be added with its pricing. `RefreshModelRegistryJob` runs that nightly in every environment, since nothing else updates the table and a gem upgrade does not touch it. A model with no pricing is billed at zero and its spend cap never fires, so the same job warns with `ai.models_without_pricing` when a model this deployment is configured to run has no price.

Every call has a purpose (`AiPurpose::POSTMORTEM`, `INCIDENT_RESPONSE`, `SUMMARY`, `MILESTONES`), and every service resolves its model through `FirefightAi.model_for(purpose, workspace:)`, most specific first:

1. The workspace's `AiModelOverride` for that purpose
2. The workspace's `AiModelOverride` for `AiPurpose::ANY`
3. The purpose's env var (`POSTMORTEM_AI_MODEL`, `INCIDENT_AI_MODEL`, `SUMMARY_AI_MODEL`, `MILESTONES_AI_MODEL`)
4. `FIREFIGHT_AI_MODEL`
5. The purpose's built-in fallback (postmortems default to a stronger model than chat responses)

The answer is a `FirefightAi::ModelChoice` (`model`, `provider`). A provider only travels with a model RubyLLM's registry cannot place on its own, such as a Bedrock or Ollama deployment: set `POSTMORTEM_AI_PROVIDER`, `FIREFIGHT_AI_PROVIDER`, or the override row's `provider`. `FirefightAi.chat(choice)` opens the chat and passes `assume_model_exists` for an unregistered model. `Inference.provider_for(model, provider:)` records the explicit provider or asks the registry, never guesses from the model name.

`AiModelOverride` rows are operator data: set from the Rails console today and from the operator console in firefight_cloud later, never from the dashboard. Self-hosters set env vars. Don't read model env vars directly in services — go through `FirefightAi.model_for`.

## Inference ledger — every call is tracked

Every row says which prompt produced it. `prompt_template` is the prompt's name and `prompt_version` is `FirefightAi::Prompt.version`, a digest of the wording itself, so an edited prompt cannot keep an old version and two wordings cannot share one. Per run values (the asker, the incident, the seed pack) are excluded, since they change every call and live in the saved chat. `PromptVersion` holds each wording once, written the first time the ledger sees it, so a version can be read back as the words the model was given. Ordering comes from when a version was first seen, not from the digest.

Every LLM call is wrapped in `Inference.track` (`app/models/inference.rb`), which records feature, provider, model, token counts (input/output/cache), `cost_micros`, latency, finish reason (`stop_reason`), the provider's request id, and status — success or error — plus who triggered it (`member` or `api_key`) and what it was about (`inferable` polymorphic).

```ruby
Inference.track(workspace:, feature:, provider:, model:, inferable: incident, member:) do
  chat = RubyLLM.chat(model: model_id)
  chat.with_instructions(system_prompt)
  chat.ask(prompt_text)
end
```

A call with `with_schema` reads its answer from `response.parsed`. `response.content` is the raw JSON text.

Never call `RubyLLM` outside an `Inference.track` block — the ledger is the cost/usage observability layer (and the substrate for AI credit billing).

## Transcript store + secret scrubbing

AI features read incident channel history from `IncidentTranscriptMessage`, not live Slack calls. Messages are scrubbed on the way in by `IncidentTranscriptMessage::Scrubbing`, which redacts secrets (AWS/GitHub/Slack/Anthropic/OpenAI/Stripe/etc. token patterns) **before persistence and before any prompt**. New secret formats belong in `SECRET_PATTERNS` there.

## Transcript access and retention

Two things gate reading a transcript from outside the product, and they answer
different questions. `Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS` is its own
grantable resource rather than part of `incidents`, because reading an incident
and reading everything said in its channel are different asks, and folding the
second into the first would have widened every grant already made. On top of
that, `Workspace#transcript_access_blocked_reason` refuses unless an admin has
turned access on under Settings, Workspace. A grant says who may ask, the
setting says whether there is anything to ask for.

`TranscriptRetentionJob` drops the raw messages once the incident they belong to
has been over for `transcript_retention_days`, nightly. The window starts at the
end rather than at close because postmortem generation reads the transcript and
one is usually written the next morning. A null retention keeps them forever,
which a workspace can choose.

**The transcript is scaffolding, the timeline is the artifact.** Milestones
already carry the decision, the quote and the person onto the timeline, and the
postmortem carries the write-up, so purging drops the conversation and not the
memory. Anything that wants to learn from past incidents should extract at close
rather than assume the messages will be there later.

Scrubbing redacts secret *formats* and nothing else. Names, customers, hostnames
and links survive it. It was built so a credential never reaches a prompt, not
so a transcript is safe to hand to a third party, which is why the surface above
it is gated twice.

## Entitlements gate

AI features are gated per workspace via `Entitlements.allows?(workspace, Entitlements::AI)`. In the open-source build this always allows (see the Entitlements section in [architecture.md](architecture.md)); the proprietary cloud build swaps in a backend enforcing trial/credit state. Gate new AI features the same way — never with a hardcoded flag.

## Milestone noting

An incident's timeline records what Firefight did. What the team worked out lives in the channel, and `FirefightAi::MilestoneExtractor` is the one pass that reads it and turns it into timeline events. It runs once per incident, from the last step of `IncidentCloseWorkflow` and `IncidentCancelWorkflow`, after the channel has already been told the incident is over. Nothing is posted to Slack.

The engine returns data and never writes. `#extract(incident, messages:, summary:, timeline:)` gives back `Milestone` structs (`kind`, `statement`, `message_id`, `confidence`). `MilestoneNotingService` does the writing, one `IncidentEvent::MILESTONE_NOTED` per milestone with the person, the quote, and the permalink stored on it. See the metadata contract in [architecture.md](architecture.md).

Three things cap what a pass can cost:

- **Once, not continuously.** No live passes, no timers, no message-count triggers. `Incident#milestones_noted_through` holds the message id of the last message read, so a reopen-and-re-resolve pass reads only what was said since, and the watermark moves even when the pass finds nothing.
- **A trimmed transcript.** `MAX_INPUT_TOKENS` caps the input, and the oldest messages are dropped first since the `IncidentSummary` passed alongside already covers them.
- **A confidence floor.** `MIN_CONFIDENCE` drops anything the model is guessing at, and a milestone citing a `message_id` that is not in the batch is discarded rather than trusted.

`FirefightAi.configuration.milestones_enabled?` is the deploy-level kill switch, read from `AI_MILESTONES_ENABLED`. Unset means on. An explicit `false`, `0`, or `off` turns the pass off for every workspace without a release, and the entitlement check still gates it per workspace underneath. With the switch off, or the entitlement blocked, `note!` returns an empty list without calling a model or moving the watermark, so the timeline is exactly what it is today.

Dismissal is error correction, not deletion. `IncidentEvent#dismiss!(by:)` stamps `dismissed_at` into the metadata and the `undismissed` scope keeps the row out of every text surface: the AI context (`Incident#to_full_context`, which feeds postmortem generation and `/ff catchup`), the Slack timeline modal, `get_incident`, and the REST timeline. The dashboard is the exception, collecting dismissed notes at the end of their day so the correction stays visible.

## Investigator

Phase 1 of the AI SRE build. Where the pieces are:

| Piece | Holds |
|---|---|
| `Investigation` | one run: the subject, trigger, who asked, budget, status |
| `Investigation::Hypothesis` | one theory |
| `Investigation::Step` | one tool call |
| `Investigation::Finding` | the one answer, with its named confidence factors |
| `Investigation::Evidence` / `Investigation::Citation` | one claim of a finding, and the steps it or a settled theory rests on |
| `Chat` / `Chat::Message` | the agent's saved conversation with the model, see Saved chat |
| `Investigation::ToolCall` | the gateway wrapper every tool call goes through, always as the agent |
| `FirefightAi::AgentLoop` / `FirefightAi::Investigator` | the loop and the prompts, in the engine |
| `Investigation::Runner` / `Investigation::Tools` | the app side of a run: the chat, the tools, what each turn spent |
| `Investigation::Delivery` | what a run says while it works, see What a run says in Slack |
| `Conversation` / `Conversation::Runner` | a person talking to the agent, see Conversations |
| `Chat::Tools` / `Chat::ToolCall` | the tools both share, and the gateway call every one goes through |
| `SystemAgent` | Firefight's own agents, global, one row each, granted per workspace |
| `Investigation::Seeding` | picks the seeder for the subject and stores its pack on `seed_pack` |
| `Investigation::IncidentSeed` | the facts Firefight already holds about an incident |
| `InvestigationService` / `InvestigationJob` | starts a run, runs it on the `investigations` queue |
| `ConversationReplyJob` | answers one chat turn, on the `conversations` queue |
| `Commands::StartInvestigation` / `Interactions::StartInvestigationButtonHandler` | the two entry points |

The rules:

- Evidence is a reference (a step, and later a PR, a file range, an Issue), never a copied blob. See Evidence points at steps below.
- **A run acts as the agent, not as the person who asked.** A conversation is the opposite, see below. `SystemAgent.investigator` is one global row, because the software is the same for every customer and only the grants differ. `Investigation::ToolCall` takes no principal argument, so no caller can run a tool as the human by mistake. A workspace grants the agent what it may reach under Gateway, Permissions, where built in agents are their own section, hidden until the workspace has `FeatureFlags::AI_SRE`. An agent granted nothing is denied, whoever asked.
- Built in agents are defined in code (`SystemAgent::BUILT_IN`) and created on demand, so a fresh install loading `schema.rb` gets them without running the migration.
- Every tool call goes through `AbilityGateway` carrying `SOURCE_INVESTIGATION`, and stores its invocation id on the step. Tool output lives on the step, encrypted, and never reaches the ledger. `params` is the binding the ledger stores, so it names what was asked and never carries a payload.
- One live run per subject, enforced by a partial unique index, so a second request is told rather than duplicating the work and posting a second answer to the same channel. It is not a cost control, budgets are.
- Both entry points ask `Investigation.unavailable_reason` and `Incident#investigation_blocked_reason` and spell no refusal of their own.
- Steps are ordered by when they happened. Branches run in parallel, so a shared counter would be a number two of them fight over.
- Budgets are code defaults in `Workspace::InvestigationLimits`, overridden per workspace by the nullable `investigation_*` columns an operator sets. The cap is in cents and spend is counted in micros, never rounded. Turns are a loop guard, not a cost unit. Each run snapshots both, so changing a default never rewrites what an old run was allowed to spend.
- `AiPurpose::INVESTIGATION` picks the model, env prefix `INVESTIGATION_AI`.
- **The subject is polymorphic.** An investigation is a bounded piece of research that ends in a finding, and an incident is the first thing worth researching, not the only one. `subject_type` plus `subject_id` replaced `incident_id`, the one live run index keys on the subject, and `Investigation#incident` returns the subject only when it is an incident, which is what the ledger's `incident_id` and the announcement's channel both ask for. A polymorphic column carries no database foreign key, so the cascade is Rails' `has_many :investigations, as: :subject, dependent: :destroy`.
- **A seeder per subject type.** `Investigation::Seeding::SEEDERS` maps a subject type to a class and a subject with no entry raises `UnknownSubject` rather than storing an empty pack. `Investigation::IncidentSeed` is the only implementation.
- **The seed pack is gathered once and stored.** The seeder reads only Firefight's own tables (the incident and its state, the lead and roles, the alerts with their provider fields, attached runbooks, and resolved past incidents that fired the same alert) and writes one jsonb blob. No model call and no tool call are involved, so the same run always produces the same pack.
- **Nothing is posted yet.** A run gathers the pack and finishes. A briefing with no answer behind it is half a feature, and the message that will carry a finding is not this one, so the posting lands with the agent loop instead.
- **People in the pack are a name and nothing else.** No platform id, so the pack is plain domain facts the engine can be handed without learning that `<@U123>` means a person. Whatever renders a mention asks the incident for it.
- A past incident matches on `alert_source_id` **and** `fingerprint`, because a fingerprint is only unique within its source, and only resolved incidents count. A match carries its `Investigation::Finding` summary when it has one.
- The pack caps alerts at `Seeding::ALERT_LIMIT` and records `alerts_held_back`, so whatever renders it can say how many it did not get. Alert `fields` are kept whole, because the agent reads them, and must be escaped by whatever renders them.

Not built yet: the dashboard page, a deadline on a run (nothing runs long enough to need one yet), and the per person environment cap on a run (the scope a person may investigate lands with the agent loop, which is what decides the environment a tool call targets). `inferences.prompt_template` and `prompt_version` exist and nothing writes them. No implementation stands behind `ConfidenceScorer` or `Matcher` yet.
- **One agent with tools, no sub-agents.** The Investigator reads every tool result into one context itself. There is no planner handing theories to branch runners and no specialist agents returning summaries, because a handoff passes on only part of what the previous step knew. Theories are `Investigation::Hypothesis` rows the same agent writes as it works.

## The agent loop

`FirefightAi::AgentLoop` drives one run over the saved chat, and `FirefightAi::Investigator` holds the prompts and the model choice. The app hands over a `Chat` record, the tools and the budget, and gets back why the run stopped. `Investigation::Runner` is the app half: it makes the chat, builds the tools, writes down what each turn spent, and turns the outcome into the run's status.

The rules:

- **Evidence points at steps, it is never a sentence on its own.** Every tool result in a run is handed over with the number its `Investigation::Step` was recorded under (`step="7"` in the frame). `conclude` takes evidence as claims, each with the step numbers it rests on, and `Investigation#conclude!` writes one `Investigation::Evidence` per claim with an `Investigation::Citation` per step. A claim that cites nothing, a step that does not exist or a step that failed raises `Investigation::Evidence::Refused`, nothing is written, and the tool hands the reason back so the agent fixes it before the run can end. Naming a cause needs at least one claim, and concluding that nothing explains it needs none. `record_hypothesis` takes steps the same way, and a theory cannot be marked supported or refuted without them, so a ruled out theory carries its why. A citation's source is polymorphic and has a `locator`, so a file range, a pull request or an Issue can be cited later without a new shape. A step also keeps its `tool_name` and a `label` such as "Get form declare", which is what the Slack message shows after each claim.
- **Only `conclude` ends a run.** It writes `Investigation::Finding` unpublished. A plain reply does nothing: the agent is reminded once, and a second one ends the run as stalled with its hypotheses kept. Theories are written as the agent goes, through `record_hypothesis`.
- **Spend is the budget.** Each model reply's cost is added to `spent_micros`, the ledger's unit and never rounded, so many small replies cost what they cost rather than a cent each. At `max_spend_cents` the agent gets one last turn to conclude with what it has, which may go slightly over. `max_turns` is only a runaway guard, and the only stop for a model whose price is unknown. A tool call id repeated in the chat ends the run, since RubyLLM would skip the tool and pay for another turn forever.
- **A model call is billed, running its tools is not.** The loop wraps only the generate move in `Inference.track`.
- **The provider is asked to cache what the agent has read.** One agent holds one growing context and resends all of it every turn, so `Investigator` and `Responder` call `with_caching` on the chat. Like tools and thinking, it is a setting on the in-memory chat, so every job applies it after loading. For Anthropic this is the automatic cache that moves forward with the conversation, and providers that cache on their own are unaffected. Opening a group changes the tool list, which sits in front of everything else in the cached prefix, so each one costs one uncached turn.
- **Every turn is written down as it happens**, so a killed worker's successor starts from what was already spent.
- **One worker per run.** `Investigation#claim!` takes a run whose lease has expired and stamps a new `lease_token`, and `record_turn!` renews that lease in the same statement that writes the turn. A worker whose token no longer matches raises `Investigation::Runner::LeaseLost`, and that job is discarded rather than retried.
- **The job that holds a run takes it back at once.** `claim!(by: job_id)` records the holder, and the same job is let in whatever the lease says. Solid Queue never runs one job in two places, and hands a job out again only once its worker is gone, so the same job coming back is proof the first worker is dead. That is what a deploy does: workers get `SolidQueue.shutdown_timeout` (five seconds) to finish, are killed, and their jobs go back on the queue, far too early for a lease to have run out. A different job, which only the sweep creates, still waits out the lease, since the first worker may only be slow. Every claim counts in `attempts`, and a run taken more than `Investigation::MAX_ATTEMPTS` times is given up on, since a run that kills every worker would otherwise be picked up forever.
- **A run is never left held by nobody.** The queue retries within seconds, far inside the lease, so `InvestigationJob` calls `Investigation#release!` before it re-raises and the retry can claim the run. An error no retry can fix (`FirefightAi::TerminalError`, such as a context the model cannot hold) ends the run at once. When a run is given up on, its thread is told, since Slack would otherwise hold a spinner over it, and offered one button to run it again, the same `Identifiers::START_INVESTIGATION` button the incident message carries. A spent budget or a person's stop gets no button, since running again would end the same way. The precise cause (`FirefightAi::Error#reason`, or the error's class) is kept in `error_summary` for debugging and is never shown in Slack or the dashboard. `InvestigationSweepJob` runs every two minutes and enqueues a job for every `Investigation.abandoned` run: one whose lease ran out, or one that was never claimed because its job was lost. A second job for one run is harmless, because the claim decides.
- **The agent starts with four tools and opens the rest.** `Investigation::Tools.for` hands over `open_tools`, `read_result`, `record_hypothesis` and `conclude`, and nothing else.
- **The agent reads a map of groups and opens the one it needs.** There is no search, so our code never guesses which tool the model means and a miss cannot pass for "I cannot check that". `Chat::Tools::Open` carries the map in its own description, one line per group, about five hundred tokens, built once per run so the front of the request stays the same. Its `group` argument is an enum of the group keys. Opening a group lists each tool with one line and offers the ones whoever acts may use, so full tool details enter the context only for groups that were opened. A group over `Open::LARGE_GROUP` tools lists first and loads only the tools the agent then names.
- **A group is the question its tools answer, never the vendor.** `Chat::Tools::Groups::FIREFIGHT` places every Firefight tool in exactly one group, and a test fails when a new tool is in none, so it cannot be left unreachable. A connected provider sits under its category from `config/integration_providers.yml`, so Datadog and Grafana share Telemetry and the agent does not need to know which one a workspace uses. A category with nothing connected still has its line and says what could be connected. A connection the registry does not know, or one in the Custom category, is its own group under the name the admin gave it, described by its tools' names. A tool has no kind of its own yet, so a provider that answers several questions sits whole under its one category.
- **The map answers in three ways**, so a gap is explainable rather than invisible: ready, exists but not granted to whoever is acting, or nothing connected. Grants still decide, and opening a group never widens them.
- **Another system's words are cleaned.** `Chat::Tools.clean` strips control characters and caps the length of every description that came from a connection, one line in a listing and `FULL_DESCRIPTION` on the tool itself. A custom connection's line in the map uses the admin's name for it and its tool names, never what the server says about itself.
- **What the agent found is remembered on the chat.** `Chat::Tools.offer_to` writes each found tool's name to `chats.found_tool_names` as it offers it, and both runners start a turn with `Chat::Tools.known`, so the next question in a chat and a resumed run do not pay for turns searching again. The tools are rebuilt from the catalog for whoever acts now, so a grant taken away since is not handed back. The order is the order they were found and never changes, because the tool list sits at the front of every request and a provider can only reuse what it has read when that front stays the same.
- **Firefight's own tools are the same classes the MCP server exposes**, so a tool never means two things and a new one reaches the agent as soon as it exists. A write the workspace granted is offered like any read, since the gateway decides. A system read leaves an `Investigation::Step` but no ledger row, which is how the gateway already treats system reads. A refusal, a pending approval or a provider failure comes back as a result the agent reads and works around, never an exception that ends the run.
- **What a tool said reaches the model inside a frame.** `FirefightAi::Evidence.frame` wraps every result from one of Firefight's own tools or a connected one in `<tool_result trust="untrusted">` and neutralises any closing tag inside it, so a file or a log line cannot end the frame early. Both prompts carry `Evidence::RULE`, so the wording and the frame live in one place. A refusal or a pending approval is Firefight speaking and is not framed. The frame is a second layer, and the permission model stays the real defence.
- **A result too large to hand over whole is saved, never cut.** `Chat::Tools.hand_over` compares a result with `Chat#result_limit`, a tenth of the running model's context window, so a model with more room is handed more and nothing is retuned. A larger result is kept in full as a `Chat::SavedResult` (encrypted, named `result_1`, `result_2` within its chat) and the model is handed `Evidence.preview`: how it starts and ends, cut between lines, how long it is, and which line shapes repeat most, which is often the clue itself. The agent always holds `read_result`, which reads a range of lines or searches, and with no result named searches everything saved in the chat, which is how two logs are lined up on one request id. Reads come back a page at a time, framed like any other result. Search is plain text, since a pattern would let a result choose what a search costs. `read_result` reads what the chat already fetched, so it goes through no gateway call and leaves no step. Counting and joining across whole logs is not what this is for, that belongs to the provider's query language and later to the read only shell. Compaction will point at the same saved results, so a shortened step can still be read again.
- **Waiting for a person does not exist yet.** A tool needing approval says so and was not run.
- **No environment is chosen.** A tool call passes no scope, so a connection with more than one environment cannot resolve one and the call is refused. Per run environment scoping lands with the approval work.

## Making room in a long run

One agent holds one context, and a real investigation reads more than a window holds. `FirefightAi::AgentLoop::Room` decides when a chat has to make room, and the chat's own record does it (`Chat::Compacting`). The loop is handed the saved chat as `memory:`, and the engine only ever calls `context_window!`, `clear_old_results!` and `rebuild!` on it.

The rules:

- **The window is known or the agent does not run.** `Chat#context_window!` reads the model registry and raises `Chat::UnknownWindow` when it holds none. Nothing is assumed in its place. `Investigation.unavailable_reason` checks it up front, so a chat, a run and a Slack mention all refuse with "not fully set up" while the log names the model (`ai.model_without_context_window`), and `RefreshModelRegistryJob` warns nightly (`ai.models_without_context_window`). A model the library does not know gets a registry row with its window, the same place it gets its price.
- **How full it is comes from the provider.** Each reply reports what the model read, fresh and cached, and what it wrote. Before a turn `Room` adds an estimate, four characters to a token, for the tool results that arrived since, which the provider has not seen yet. After a compaction the last count no longer describes the chat, so the estimate covers the whole chat until the next reply.
- **Stage one, at half the window, clears old tool results.** No model call. `clear_old_results!` keeps the newest `KEEP_RECENT` whole and moves each older one into a `Chat::SavedResult`, leaving a framed line that keeps its tool and step and names where the full text went. The agent reads it again with `read_result`, which is free and never touches the provider it came from. A result that was already saved because it was large is pointed at, not saved twice. A clear that would free under `MIN_FREED_SHARE` of the window is skipped, since every clear costs one uncached turn.
- **Stage two, at three quarters, rebuilds.** Only when clearing did not free enough. The agent first gets one turn with no tools to write itself a note with everything still in view, billed like any turn. `rebuild!` then saves every remaining result, marks the working messages `archived_at` and starts again from one message: `owner.memory_brief` (for a run the seed pack, each theory with where it stands and the steps it rests on, and every step), the saved results, the note, and the last `RECENT_IN_FULL` results whole. The instructions are applied again word for word, never summarised.
- **A conversation is never put away.** `Conversation#keeps_in_memory?` keeps what the person and the agent said to each other and puts away only the work in between. The note is marked like a nudge, so it is never read back as something the agent said to the person.
- **Nothing is deleted.** `sent_messages` is what the model is sent, `messages` is everything, which is what a person reads and a replay needs. Step numbers never change, so a citation made before a rebuild still means the same step after it.
- **The backstop.** A provider that still says too long gets the chat rebuilt without a note, since the model cannot be asked, and one more try. A second refusal ends the run.
- **Every event is a `Chat::Compaction`** with the stage, the tokens in use before, what was freed and how many messages it touched, so the two thresholds are tuned from what really happened. Nothing is shown in Slack or the dashboard.
- **Not used: the provider's own compaction.** It differs per provider, cannot point back at our steps, and does not exist on an open source model.

## Similarity search

`SearchEmbedding` holds one vector per record, and `search_similar` is how the agent asks what looks like a situation rather than what matches its words. Incidents, findings and postmortems are embedded, and pgvector does the ranking.

The rules:

- **Every incident is searchable, open ones included**, since a live incident that reads like a past one is the point. A match says whether it is still open, so an unfinished one is not presented as an answer.
- **An incident is embedded from what people wrote**: its name, summary, alert titles, the summaries it had along the way and its milestone notes. Not its status changes, which say nothing about what happened.
- **The embedding model is its own purpose** (`AiPurpose::EMBEDDING`, `EMBEDDING_AI_MODEL`) and deliberately not overridable per workspace. Every vector in a workspace must come from one model, so changing it means writing them all again.
- **A record is embedded again only when its words change.** The row keeps a digest, and `WriteSearchEmbeddingJob` writes nothing when it matches.
- **Asking for a vector is a call to another system, so it lives in `SearchEmbeddingService`.** `write!(record)` and `similar_to(query)` are the only two places `FirefightAi.embed` is called. The models say what to embed (`search_text`, `search_embeddable?`) and rank a given vector (`SearchEmbedding.nearest`), and never call the engine.
- **Nothing is backfilled.** Records written before this landed have no vector until they change.
- **pgvector is required**, and the column is fixed at 1536 numbers wide.
- **A postmortem is embedded once it is completed**, not on every save while someone is still writing it.
- **The search is authorized as an incident read**, so a finding is left out unless the caller also holds `investigations.read`. The types a caller may see are decided per call.
- **Rows written by an older embedding model are ignored**, since a vector from one model says nothing about a vector from another. Changing the model makes search quiet until records are written again.
- **The tool is an MCP tool**, so our agent reaches it through its grants and an outside agent gets the same thing.

## Conversations

A `Conversation` is a person talking to the agent, and an investigation is the job it starts when a question needs real work. Both run on `FirefightAi::AgentLoop`, share `Chat::Tools` and save their chat in the same table. `FirefightAi::Responder` holds the prompt, `Conversation::Runner` is the app half, and `Conversation::Delivery` is what it says while it answers.

The rules:

- **A mention is the entry point.** `@Firefight` in an incident channel reaches the agent once `FeatureFlags::AI_SRE` is on, and the old `IncidentResponder` answer stands for every workspace without the flag.
- **One conversation per thread.** `Conversation::Opener` joins the one already there, so a second mention continues rather than starting over, and the unique index on workspace, channel and thread is the guard.
- **A reply ends the turn.** `reply_is_answer` is the only difference in the loop: in a chat the person is waiting, so plain text is the answer, and in a run only `conclude` ends it.
- **The agent hands real work over** with `start_investigation`, which starts a run in the same channel rather than doing the work in the chat.
- **A run started from a chat is recorded as one.** `Investigation::TRIGGER_CONVERSATION`, not the command trigger, so the record says where it came from.
- **A tool that takes a whole form is shown as the form's fields.** `Chat::Tools.shown_arguments` flattens an argument whose value is a flat hash, such as `answers` on `declare_incident`, into one row per field, so the headline is the incident's name and a reader never sees a Ruby hash. Any other nested value is one line of JSON.
- **A call that refused or errored is marked failed.** The words still go to the model, but `ruby_llm_tool_calls.failed` is set by the wrappers (`Chat::Tools.mark_failed`) on a denial, a tool error or an error response, and both the live step event and the saved serializer report `STATUS_FAILED`, so a card says Failed rather than Completed.
- **An outside agent asks over MCP.** `ask_halon` runs one turn synchronously as whoever the credential resolves to, on a `KIND_MCP` conversation kept per principal, with `Conversation::QuietDelivery` so nothing streams. `start_investigation` and `get_investigation` do the same for runs. See docs/mcp.md, Halon, the agent.
- **A step is told apart by what its tool was given.** `Chat::Tools.headline_for` takes an argument named for what is being looked for (`query`, `name`, `identifier`, `title`), and otherwise the first argument the tool's own schema requires, so four reads of four forms show as "Get form declare", "Get form update" and so on rather than four identical rows. A tool with nothing required has no headline rather than a guessed one, and `incident` is the headline of last resort, since it is where a step happens rather than what tells it apart, so it names a step only when nothing else does (`Chat::Tools::LAST_RESORT_HEADLINE`): "Assign incident role incident_lead", but "Resolve incident INC-001". The dashboard keys each row by the step's own key, never by its words.
- **Some results are cards.** A step carries a `card` (`Chat::Tools.card_for`), a reference to what to draw and never the data, on the live step event and the saved step alike, and only once the step is done. The page draws it after the answer (`AgentCard` picks the component by `AGENT_CARD_KINDS`) and reads the rows from its own props, so a card tells the truth after the person acts on it. In a Slack thread `Conversation::Delivery` posts it under the answer through `post_integration_card`. The first kind is a category of integrations, from `list_integrations`.
- **Setting up happens in the chat, connecting does not.** The chat prompt walks someone who asks to set up Firefight through it one step at a time, most useful missing piece first, and changes a setting only once they agree. Integrations are only ever shown as a card: the prompt says never to ask for, accept or repeat a key, token or password. The start page offers "Set up Firefight" to whoever may change the workspace.
- **A connection tool is offered the same way in a chat and over MCP.** `Integration::Tool#offered_schema` is the provider's schema plus `environment`, listed as an enum when the connection is wired per environment (`Integration#environment_choices`), and both `Chat::Tools::Connection` and `Mcp::ConnectionToolFactory` hand it out. The named environment resolves once, on the model (`Integration#environment_entry_for`), and becomes the gateway scope the grant is checked against, so a per environment connection is reachable from a chat and an unknown name is refused with the same words everywhere.
- **A tool's choices are the workspace's own.** Roles, severities and statuses are listed in the tool's parameter description when it is offered (`Base.schema_for`, see docs/mcp.md), and a person parameter takes `"me"`. The chat prompt says to pick from a listed choice, to ask which when several fit, and never to ask a person for their own email.
- **A step is shown running for at least a moment.** A tool usually answers within a few dozen milliseconds, so a step's running and done events land in the same frame and the spinner would never paint. `useSettledSteps` on the page shows each step running for `SHOW_RUNNING_FOR_MS` and settles steps that finished together `SETTLE_APART_MS` apart, in the order they finished. The saved status underneath is untouched, a reload shows the truth.
- **The agent keeps how it works to itself.** The chat prompt tells it never to mention its tools, the groups or how it found something, unless the person asks or it is the reason something could not be done.
- **Looking something up is shown as thinking, changing something as a card.** `Chat::Tools.kind` calls a step `KIND_READ` when its tool is read only, from the MCP annotation for Firefight's own tools and from `integration_tools.read_only` for a connected one, and `KIND_ACT` otherwise. The dashboard collapses consecutive read steps into one `thinking-state` trace with the seconds they took, and renders act steps as task rows. Slack shows every step the same way.
- **Long running work has its own workers, and nothing else picks it up.** An investigation runs for minutes and a person is waiting on a chat answer, so `investigations` and `conversations` are separate queues with a worker each in `config/queue.yml`. No worker takes `"*"`, since a wildcard would pick up the long running queues too and a flood of investigations would hold the threads every other job needs. The general worker lists its queues by name, and `test/config/queue_config_test.rb` fails when a job or a scheduled task asks for a queue no worker has, so a new queue cannot be left with nobody working it.
- **One turn at a time per conversation.** `ConversationReplyJob` limits concurrency on the conversation id, so a second question asked while the agent works waits, then is answered after the first. Without it the two turns corrupt the chat. RubyLLM saves a blank assistant row while it calls the model, and `Chat#discard_interrupted_reply!` cannot tell that row from one a killed worker left behind, so the second turn deletes the first turn's live row and orphans its tool results. No provider will read a history like that. The lock expires after `TURN_CEILING`, since a turn still holding it belongs to a worker that died.
- **A reply the platform refuses is logged, never retried.** The answer is already in the chat and the turn is paid for, so a retry would buy a second model call for nothing.
- **The budget is per question**, `Workspace::InvestigationLimits::CONVERSATION_DEFAULT_*`, smaller than a run's. `Conversation::Runner` hands the loop a budget that starts at zero, so a long chat never runs dry for good, and `Conversation#add_turn!` adds what each turn spent to the conversation's running totals in SQL. A question that runs out says so rather than going quiet. A turn resumed after a confirmation starts a fresh budget too.
- **The loop's nudges are marked.** The reminder and the last turn notice are saved as the user's side of the chat, which is how a model reads them. The engine writes them through the `nudge:` hook, `Chat#nudge!` sets `chat_messages.nudge`, and `readable_messages` and the list preview leave them out, since the content is encrypted and nothing else could tell them from the person's words. Rows written before the column existed are not marked.
- **A conversation acts as the person who asked that turn.** `Conversation::Turn` carries the asker, and every tool call runs with their permissions, the same ones they have in the dashboard. An admin can manage permissions through chat, and a member is refused where the dashboard would refuse them, with a result naming who can do it. The asker travels with the job (`ConversationReplyJob` takes their id), since in a Slack thread each tag can come from someone else. `Chat::Tools.catalog` is built for whoever acts, so a member is offered what a member may use. An investigation still acts as the agent, below.
- **Every tool call is ledgered** as the person with `AbilityGateway::SOURCE_CONVERSATION`, which is what says it came through the agent. A conversation writes no `Investigation::Step`, since it has no run to record.
- **Firefight's own tools run through `Mcp::ToolDispatcher.run`**, the same path the MCP server uses, so a tool that acts as someone (`perform_with_principal`) gets the asker, and its errors read the same in chat as over MCP. The action is worked out from the arguments at call time, since an upsert is a create or an update depending on its target.
- **Some changes wait for the person to confirm.** `Conversation::Turn#confirms?` pauses a tool call when its action is `RISK_DESTRUCTIVE` or not `reversible`, when the tool itself is annotated destructive (`update_workspace_settings`, whose update verb would otherwise not ask), or when an approval rule covers it and the asker may approve it themselves (`Ability::Approval.self_approvable_by?`). An investigation never pauses. The tool's `requires_approval?` asks this, RubyLLM stops before the call, and `AgentLoop` ends the turn with `STATUS_WAITING` rather than calling the model again. The runner marks the calls `Chat::APPROVAL_REQUESTED` and asks. The dashboard shows an approval card, and Slack posts a message with Confirm and Cancel buttons (`Identifiers::AGENT_CONFIRM`, `AGENT_CANCEL`). `Conversation::Confirming.decide` records each answer with one guarded update under a row lock, and only the answer that settles the last open question enqueues `ConversationReplyJob`, as whoever answered. The resumed turn is handed back the tools the model already called. When an approval rule gates a confirmed call, confirming approves that `Ability::Approval` as the asker and the call runs. A cancelled call returns RubyLLM's denial, and the agent says the person cancelled it.

## What a run says in Slack

`Investigation::Delivery` is everything a run says while it works, and the adapter decides how it looks. A run posts "Investigating INC-001" in the incident channel, opens an agent session on that message's thread, reports each tool as a step, and closes with the answer or with why it stopped.

The rules:

- **Firefight is declared a Slack agent.** `features.agent_view` and the `assistant:write` scope in `config/slack_manifests/template.yml`. The declaration cannot be reversed, the scope forces a reinstall, and the features need a paid Slack plan.
- **The session status is ours to clear.** Slack holds its spinner for an hour unless the session is set back to `active`, so `finish_agent_answer` always clears it, including when the run failed.
- **A workspace without the agent features still gets the answer.** `start_agent_answer` returns no answer id when Slack refuses, and the finish posts one ordinary threaded message instead. A step against no answer id is dropped.
- **Steps come from the engine**, which reports a tool as the agent reaches for it and again when it answers. `conclude` and `record_hypothesis` are not shown, since they are how the agent writes rather than what it looked at.
- **Thumbs are Slack's own feedback element**, and every vote is kept as an `Investigation::Verdict`, one per person, changeable. The finding carries an outcome only while the room agrees, so a split leaves it blank, and `Finding#tally` is the count the Learner reads later.
- **Stop is Slack's own button.** It needs the `agent_session_stopped` subscription or Slack shows a dead spinner. The event sets `cancel_requested`, the loop sees it between turns, and `Chat#cancel` stops a model call already in flight. The run ends as canceled.
- **Blocks are attached when the stream stops**, never mid stream, since Slack may otherwise break them up.

## Saved chat

`Chat` and `Chat::Message` hold the agent's conversation with the model: messages, thinking text and signatures, raw reasoning and content blocks, tool calls and results, approval decisions. `owner` is polymorphic and unique, so an investigation has one chat and a conversation will too, and the owner decides who may read it. RubyLLM's `acts_as_chat` and `acts_as_message` write each move as it happens, and `chat.to_llm` rebuilds the `RubyLLM::Chat`. The engine only sees that `RubyLLM::Chat`.

The rules:

- **Resume from the chat.** Rebuilding from `Investigation::Step` loses the reasoning between tool calls and the thinking blocks providers need back unchanged.
- **Call `Chat#discard_interrupted_reply!` before resuming.** A worker killed mid tool call leaves an empty assistant row that RubyLLM reads as the final answer. Only the job holding the run may call it, since a live worker mid tool call has the same row. The interrupted tool runs again, so tools must be safe to repeat.
- **Tool call ids are unique per message**, not globally as RubyLLM installs them, since a model that numbers its calls (`call_0`) repeats ids across workspaces.
- **Everything the model read or said is encrypted**: `content`, `thinking_text`, `thinking_signature`, `citations`, `server_tool_calls`, `raw_content`, `raw_reasoning`. Tool call `arguments` in `ruby_llm_tool_calls` are not, like ledger `params`.
- **A chat belongs to its owner's workspace.**
- **Settings are not saved.** Tools, thinking and temperature live on the in-memory chat, so every job applies them after loading.
- **Always set the model**, from `FirefightAi.model_for`. Without one RubyLLM uses its `default_model`. The first chat ever saved copies RubyLLM's 1,669 models into `ruby_llm_models`, and `test/fixtures/ruby_llm_models.yml` keeps one row so tests skip that.
- **Model lookups never read `ruby_llm_models`.** RubyLLM's Rails support would point `RubyLLM.models` at it, a copy no gem upgrade refreshes, so the engine clears `model_registry_store` on `:active_record` load.
- **Spend is not read from here.** `ruby_llm_usages` records tokens and cost per attempt, but spend, permissions and audit stay in `Inference`, the gateway and `Investigation::Step`.
- Only Anthropic's thinking replay has been tested against saved rows, not OpenAI's or Gemini's.

## Postmortem generation state

`Postmortem#status` is the document's editorial status and nothing else. Whether an AI generation is writing the document lives in `generation_state` (`generating`, `failed`, or nil for nobody). Every entry point (the dashboard button, `/ff postmortem`, the Slack home menu, the button on the resolution message, the API and the MCP tool) calls `PostmortemGenerationService#start!(incident, by:)`, which creates the placeholder through `Postmortem.start_generation!` or re-arms a failed one and enqueues the job, and does nothing when a generation is already running, so two requests yield one job. The job runs only while the state is `generating`. A terminal failure marks the row `failed` with the error's reason instead of deleting it, and so does any error the engine did not classify, so the page never polls a placeholder forever. A failed placeholder blocks nothing: `Incident#postmortem_blocked_reason` ignores it, so Try again re-arms it and Start blank turns it into the empty document. `Postmortem.complete_generation!` clears the state when it saves the draft.

## Postmortem sections are honest

The model is asked for the sections in `FirefightAi::Schemas::Postmortem`, and every one of them is nullable. Nullable rather than optional because strict structured output (OpenAI refuses a schema whose `required` list does not name every property) wants every key present, so null is how the model says the record has nothing for a section. The prompt says to write only what the incident record supports and to return null rather than infer a cause, an impact or a fix from the title and the duration. A blank incident used to come back as nine confident sections of fiction. Now `Postmortem.complete_generation!` renders every heading in `Postmortem::SECTION_KEYS` regardless, puts `Postmortem::EMPTY_SECTION_PLACEHOLDER` under any the model returned as null, and builds the Timeline section itself from `Postmortem::TimelineSection` (the undismissed incident events, capped like the generator's own timeline input) so that one section is factual on every document. The placeholder is the app's copy, never the model's, so it cannot drift between runs.
