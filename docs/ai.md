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

**Errors stop at the engine boundary.** Every model call runs inside `FirefightAi.translating_errors`, which maps the client library's exceptions to `FirefightAi::TransientError` (worth retrying) and `FirefightAi::TerminalError` (retrying gives the same answer). Both carry `reason`, the client error's own name, for failure messages. App jobs `retry_on` the first and `discard_on` the second and never name the client library.

## Model-agnostic by configuration

The engine calls models through `RubyLLM` — no provider-specific SDK code in services. Every provider RubyLLM supports is configured the same way: one env var per RubyLLM setting, named after it. `FirefightAi::Configuration::PROVIDER_SETTINGS` is the list (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `BEDROCK_REGION`, `VERTEXAI_SERVICE_ACCOUNT_KEY`, `OLLAMA_API_BASE`, `OPENROUTER_API_KEY`, ...). `config/initializers/firefight_ai.rb` reads them into `configuration.provider_settings` and the engine hands them to `RubyLLM.configure` untouched, so adding a provider RubyLLM gains is one entry in the list. Bedrock takes its AWS credentials from the SDK's usual environment. OpenAI is pinned to the Chat Completions protocol (`openai_protocol`), since RubyLLM 2 defaults it to the Responses API and OpenAI compatible bases may not serve that.

Every call has a purpose (`AiPurpose::POSTMORTEM`, `INCIDENT_RESPONSE`, `SUMMARY`, `MILESTONES`), and every service resolves its model through `FirefightAi.model_for(purpose, workspace:)`, most specific first:

1. The workspace's `AiModelOverride` for that purpose
2. The workspace's `AiModelOverride` for `AiPurpose::ANY`
3. The purpose's env var (`POSTMORTEM_AI_MODEL`, `INCIDENT_AI_MODEL`, `SUMMARY_AI_MODEL`, `MILESTONES_AI_MODEL`)
4. `FIREFIGHT_AI_MODEL`
5. The purpose's built-in fallback (postmortems default to a stronger model than chat responses)

The answer is a `FirefightAi::ModelChoice` (`model`, `provider`). A provider only travels with a model RubyLLM's registry cannot place on its own, such as a Bedrock or Ollama deployment: set `POSTMORTEM_AI_PROVIDER`, `FIREFIGHT_AI_PROVIDER`, or the override row's `provider`. `FirefightAi.chat(choice)` opens the chat and passes `assume_model_exists` for an unregistered model. `Inference.provider_for(model, provider:)` records the explicit provider or asks the registry, never guesses from the model name.

`AiModelOverride` rows are operator data: set from the Rails console today and from the operator console in firefight_cloud later, never from the dashboard. Self-hosters set env vars. Don't read model env vars directly in services — go through `FirefightAi.model_for`.

## Inference ledger — every call is tracked

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
| `Chat` / `Chat::Message` | the agent's saved conversation with the model, see Saved chat |
| `Investigation::ToolCall` | the gateway wrapper every tool call goes through, always as the agent |
| `FirefightAi::AgentLoop` / `FirefightAi::Investigator` | the loop and the prompts, in the engine |
| `Investigation::Runner` / `Investigation::Tools` | the app side of a run: the chat, the tools, what each turn spent |
| `SystemAgent` | Firefight's own agents, global, one row each, granted per workspace |
| `Investigation::Seeding` | picks the seeder for the subject and stores its pack on `seed_pack` |
| `Investigation::IncidentSeed` | the facts Firefight already holds about an incident |
| `InvestigationService` / `InvestigationJob` | starts a run, runs it on the `investigations` queue |
| `Commands::StartInvestigation` / `Interactions::StartInvestigationButtonHandler` | the two entry points |
| `FirefightAi::Contracts::*` | the reasoning shapes that are swappable, `ConfidenceScorer` and `Matcher` |

The rules:

- Evidence is a reference (a ledger invocation, a PR, a file range, an incident), never a copied blob.
- **A run acts as the agent, not as the person who asked.** `SystemAgent.investigator` is one global row, because the software is the same for every customer and only the grants differ. `Investigation::ToolCall` takes no principal argument, so no caller can run a tool as the human by mistake. A workspace grants the agent what it may reach under Gateway, Permissions, where built in agents are their own section, hidden until the workspace has `FeatureFlags::AI_SRE`. An agent granted nothing is denied, whoever asked.
- Built in agents are defined in code (`SystemAgent::BUILT_IN`) and created on demand, so a fresh install loading `schema.rb` gets them without running the migration.
- Every tool call goes through `AbilityGateway` carrying `SOURCE_INVESTIGATION`, and stores its invocation id on the step. Tool output lives on the step, encrypted, and never reaches the ledger. `params` is the binding the ledger stores, so it names what was asked and never carries a payload.
- One live run per subject, enforced by a partial unique index, so a second request is told rather than duplicating the work and posting a second answer to the same channel. It is not a cost control, budgets are.
- Both entry points ask `Investigation.unavailable_reason` and `Incident#investigation_blocked_reason` and spell no refusal of their own.
- Steps are ordered by when they happened. Branches run in parallel, so a shared counter would be a number two of them fight over.
- Budgets are code defaults in `Workspace::InvestigationLimits`, overridden per workspace by the nullable `investigation_*` columns an operator sets. Spend is cents. Turns are a loop guard, not a cost unit. Each run snapshots both, so changing a default never rewrites what an old run was allowed to spend.
- `AiPurpose::INVESTIGATION` picks the model, env prefix `INVESTIGATION_AI`.
- **The subject is polymorphic.** An investigation is a bounded piece of research that ends in a finding, and an incident is the first thing worth researching, not the only one. `subject_type` plus `subject_id` replaced `incident_id`, the one live run index keys on the subject, and `Investigation#incident` returns the subject only when it is an incident, which is what the ledger's `incident_id` and the announcement's channel both ask for. A polymorphic column carries no database foreign key, so the cascade is Rails' `has_many :investigations, as: :subject, dependent: :destroy`.
- **A seeder per subject type.** `Investigation::Seeding::SEEDERS` maps a subject type to a class and a subject with no entry raises `UnknownSubject` rather than storing an empty pack. `Investigation::IncidentSeed` is the only implementation.
- **The seed pack is gathered once and stored.** The seeder reads only Firefight's own tables (the incident and its state, the lead and roles, the alerts with their provider fields, attached runbooks, and resolved past incidents that fired the same alert) and writes one jsonb blob. No model call and no tool call are involved, so the same run always produces the same pack.
- **Nothing is posted yet.** A run gathers the pack and finishes. A briefing with no answer behind it is half a feature, and the message that will carry a finding is not this one, so the posting lands with the agent loop instead.
- **People in the pack are a name and nothing else.** No platform id, so the pack is plain domain facts the engine can be handed without learning that `<@U123>` means a person. Whatever renders a mention asks the incident for it.
- A past incident matches on `alert_source_id` **and** `fingerprint`, because a fingerprint is only unique within its source, and only resolved incidents count. A match carries its `Investigation::Finding` summary when it has one.
- The pack caps alerts at `Seeding::ALERT_LIMIT` and records `alerts_held_back`, so whatever renders it can say how many it did not get. Alert `fields` are kept whole, because the agent reads them, and must be escaped by whatever renders them.

Not built yet: the posted Finding, MCP tools, the dashboard page, a deadline on a run (nothing runs long enough to need one yet), and the per person environment cap on a run (the scope a person may investigate lands with the agent loop, which is what decides the environment a tool call targets). `inferences.prompt_template` and `prompt_version` exist and nothing writes them. No implementation stands behind `ConfidenceScorer` or `Matcher` yet.
- **One agent with tools, no sub-agents.** The Investigator reads every tool result into one context itself. There is no planner handing theories to branch runners and no specialist agents returning summaries, because a handoff passes on only part of what the previous step knew. Theories are `Investigation::Hypothesis` rows the same agent writes as it works.

## The agent loop

`FirefightAi::AgentLoop` drives one run over the saved chat, and `FirefightAi::Investigator` holds the prompts and the model choice. The app hands over a `Chat` record, the tools and the budget, and gets back why the run stopped. `Investigation::Runner` is the app half: it makes the chat, builds the tools, writes down what each turn spent, and turns the outcome into the run's status.

The rules:

- **Only `conclude` ends a run.** It writes `Investigation::Finding` unpublished. A plain reply does nothing: the agent is reminded once, and a second one ends the run as stalled with its hypotheses kept. Theories are written as the agent goes, through `record_hypothesis`.
- **Spend is the budget.** Each model reply's cost is added to `spent_cents`, and at `max_spend_cents` the agent gets one last turn to conclude with what it has, which may go slightly over. `max_turns` is only a runaway guard, and the only stop for a model whose price is unknown. A tool call id repeated in the chat ends the run, since RubyLLM would skip the tool and pay for another turn forever.
- **A model call is billed, running its tools is not.** The loop wraps only the generate move in `Inference.track`.
- **Every turn is written down as it happens**, so a killed worker's successor starts from what was already spent.
- **One worker per run.** `Investigation#claim!` takes a run whose lease has expired and stamps a new `lease_token`, and `record_turn!` renews that lease in the same statement that writes the turn. A worker whose token no longer matches raises `Investigation::Runner::LeaseLost`, and that job is discarded rather than retried.
- **Tools come from the agent's own grants.** `Investigation::Tools.for` offers `record_hypothesis`, `conclude` and every connection tool `Integration::Tool#callable_by?` allows for `SystemAgent.investigator`, under the action key with dots turned into underscores. A refusal, a pending approval or a provider failure comes back as a result the agent reads and works around, never an exception that ends the run.
- **Waiting for a person does not exist yet.** A tool needing approval says so and was not run.
- **No environment is chosen.** A tool call passes no scope, so a connection with more than one environment cannot resolve one and the call is refused. Per run environment scoping lands with the approval work.

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
