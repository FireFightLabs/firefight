# AI (firefight_ai engine)

All AI features live in the `engines/firefight_ai/` engine. Read this before touching AI generation, the inference ledger, or the transcript store.

## Structure

```
engines/firefight_ai/
  lib/firefight_ai/configuration.rb                  # default_model, openai_api_key, request_timeout
  app/services/firefight_ai/
    postmortem_generator.rb                          # Timeline + transcript → structured postmortem draft
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

The engine calls models through `RubyLLM` — no provider-specific SDK code in services. Every provider RubyLLM supports is configured the same way: one env var per RubyLLM setting, named after it. `FirefightAi::Configuration::PROVIDER_SETTINGS` is the list (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `BEDROCK_REGION`, `VERTEXAI_SERVICE_ACCOUNT_KEY`, `OLLAMA_API_BASE`, `OPENROUTER_API_KEY`, ...). `config/initializers/firefight_ai.rb` reads them into `configuration.provider_settings` and the engine hands them to `RubyLLM.configure` untouched, so adding a provider RubyLLM gains is one entry in the list. Bedrock takes its AWS credentials from the SDK's usual environment.

Every call has a purpose (`AiPurpose::POSTMORTEM`, `INCIDENT_RESPONSE`, `SUMMARY`, `MILESTONES`), and every service resolves its model through `FirefightAi.model_for(purpose, workspace:)`, most specific first:

1. The workspace's `AiModelOverride` for that purpose
2. The workspace's `AiModelOverride` for `AiPurpose::ANY`
3. The purpose's env var (`POSTMORTEM_AI_MODEL`, `INCIDENT_AI_MODEL`, `SUMMARY_AI_MODEL`, `MILESTONES_AI_MODEL`)
4. `FIREFIGHT_AI_MODEL`
5. The purpose's built-in fallback (postmortems default to a stronger model than chat responses)

The answer is a `FirefightAi::ModelChoice` (`model`, `provider`). A provider only travels with a model RubyLLM's registry cannot place on its own, such as a Bedrock or Ollama deployment: set `POSTMORTEM_AI_PROVIDER`, `FIREFIGHT_AI_PROVIDER`, or the override row's `provider`. `FirefightAi.chat(choice)` opens the chat and passes `assume_model_exists` for an unregistered model. `Inference.provider_for(model, provider:)` records the explicit provider or asks the registry, never guesses from the model name.

`AiModelOverride` rows are operator data: set from the Rails console today and from the operator console in firefight_cloud later, never from the dashboard. Self-hosters set env vars. Don't read model env vars directly in services — go through `FirefightAi.model_for`.

## Inference ledger — every call is tracked

Every LLM call is wrapped in `Inference.track` (`app/models/inference.rb`), which records feature, provider, model, token counts (input/output/cache), `cost_micros`, latency, stop reason, and status — success or error — plus who triggered it (`member` or `api_key`) and what it was about (`inferable` polymorphic).

```ruby
Inference.track(workspace:, feature:, provider:, model:, inferable: incident, member:) do
  chat = RubyLLM.chat(model: model_id)
  chat.with_instructions(system_prompt)
  chat.ask(prompt_text)
end
```

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

## Postmortem generation state

`Postmortem#status` is the document's editorial status and nothing else. Whether an AI generation is writing the document lives in `generation_state` (`generating`, `failed`, or nil for nobody). Every entry point (the dashboard button, `/ff postmortem`) calls `Postmortem.start_generation!(incident, by:)`, which creates the placeholder or re-arms a failed one and returns nil when a generation is already running, so two requests yield one job. The job runs only while the state is `generating`; a terminal failure marks it `failed` with the error's reason instead of deleting the row, and the page offers Try again or Start blank. `Postmortem.complete_generation!` clears the state when it saves the draft.
