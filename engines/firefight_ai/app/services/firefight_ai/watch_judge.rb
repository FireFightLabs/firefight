module FirefightAi
  # What a watch asks a model, only when a reading changed and no rule the watch was given decides it: whether the new
  # reading shows the goal reached, failed or still going, and once something failed, why, from the logs a watch read.
  # One call with no tools, on the workspace's quick model. The app reads and keeps everything, this only judges text.
  class WatchJudge
    FEATURE = "watch".freeze
    Reading = Data.define(:state, :said)

    def initialize(workspace, inferable: nil, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    def reading(goal:, before:, now:)
      content = ask(READING_PROMPT, Schemas::WatchReading, "## The goal\n#{goal}\n\n## The reading before\n#{before.presence || '(none)'}\n\n## The reading now\n#{now}")
      state = content[:state].presence_in([ Schemas::WatchReading::DONE, Schemas::WatchReading::FAILED, Schemas::WatchReading::GOING ])
      Reading.new(state: state || Schemas::WatchReading::GOING, said: content[:said].to_s.strip)
    end

    # One or two sentences saying why it failed, from what was read, or nil when the evidence does not say.
    def why_failed(what:, evidence:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(WHY_PROMPT)) do |chat|
        chat.with_instructions(WHY_PROMPT)
        chat.ask("## What failed\n#{what}\n\n## What was read\n#{evidence}")
      end
      said = response.content.to_s.strip
      said.presence unless said.casecmp?(UNKNOWN)
    end

    # Where what happened leaves the goal the person had, and the next step offered as a question, or nil when nothing
    # useful can be said.
    def standing(purpose:, happened:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(STANDING_PROMPT)) do |chat|
        chat.with_instructions(STANDING_PROMPT)
        chat.ask("## What the person wanted\n#{purpose}\n\n## What just happened\n#{happened}")
      end
      said = response.content.to_s.strip
      said.presence unless said.casecmp?(UNKNOWN)
    end

    UNKNOWN = "unknown".freeze

    READING_PROMPT = <<~PROMPT.freeze
      A person asked to be told when something in a production system is done. You get the goal, the last reading and the new one. Say whether the new reading shows the goal reached (done), something gone wrong such as a failed or crashed state (failed), or neither yet (going).

      - Judge only from the reading. Never guess at what is not in it.
      - When unsure, it is going.
      - #{Punctuation::RULE}
    PROMPT

    WHY_PROMPT = <<~PROMPT.freeze
      Something a person was waiting on failed in a production system. You get what failed and what was read about it, such as the end of a build or job log. Say why it failed in one or two short plain sentences, naming the step, error or test that the evidence shows.

      - Use only the evidence. Quote an error message briefly when it says it best.
      - When the evidence does not show why, answer exactly: #{UNKNOWN}
      - #{Punctuation::RULE}
    PROMPT

    # Seen in a real chat, a manual deploy was reported as a success when what the person wanted was the webhook path
    # fixed, and later nobody could say why it had been run.
    STANDING_PROMPT = <<~PROMPT.freeze
      A person asked Halon to follow something in a production system for a goal of theirs. You get the goal in their words and what just happened. Say in one short sentence where this leaves the goal, then offer the most useful next step as a question, such as "The manual run worked, but the GitHub path is still broken. Next I would read the webhook's error, shall I?"

      - Use only what happened. Never say the goal is reached unless what happened shows it.
      - Never offer a fix that what happened does not show the cause of. When the cause is unknown, offer the check that would show it.
      - Offer to do it. Never say it was done.
      - At most two sentences, plain words, no preamble.
      - When nothing useful can be said, answer exactly: #{UNKNOWN}
      - #{Punctuation::RULE}
    PROMPT

    private

    def ask(prompt, schema, text)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context(prompt)) do |chat|
        chat.with_instructions(prompt)
        chat.with_schema(schema)
        chat.ask(text)
      end
      response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    def inference_context(prompt)
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, member: @member, prompt_template: FEATURE, prompt_version: Prompt.version(prompt), prompt_text: prompt
      }
    end
  end
end
