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
    schemas/postmortem.rb                            # Structured-output schema for postmortem generation
  app/jobs/firefight_ai/
    postmortem_generation_job.rb                     # Async wrapper for the generator. Runs only while Postmortem#generation_state is "generating"
    incident_response_job.rb                         # Async wrapper for the responder
```

## Model-agnostic by configuration

The engine calls models through `RubyLLM` — no provider-specific SDK code in services. Configuration is wired in `config/initializers/firefight_ai.rb`:

```ruby
FirefightAi.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key)
  config.default_model  = ENV.fetch("FIREFIGHT_AI_MODEL", "gpt-4o-mini")
end
```

Self-hosters point `FIREFIGHT_AI_MODEL` (and the relevant API key) at their own provider. Don't hardcode model names in services — use the configuration.

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

## Entitlements gate

AI features are gated per workspace via `Entitlements.allows?(workspace, Entitlements::AI)`. In the open-source build this always allows (see the Entitlements section in [architecture.md](architecture.md)); the proprietary cloud build swaps in a backend enforcing trial/credit state. Gate new AI features the same way — never with a hardcoded flag.

## Postmortem generation state

`Postmortem#status` is the document's editorial status and nothing else. Whether an AI generation is writing the document lives in `generation_state` (`generating`, `failed`, or nil for nobody). Every entry point (the dashboard button, `/ff postmortem`) calls `Postmortem.start_generation!(incident, by:)`, which creates the placeholder or re-arms a failed one and returns nil when a generation is already running, so two requests yield one job. The job runs only while the state is `generating`; a terminal failure marks it `failed` with the error class instead of deleting the row, and the page offers Try again or Start blank. The generator clears the state when it saves.
