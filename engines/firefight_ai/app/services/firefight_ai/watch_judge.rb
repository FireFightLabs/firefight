module FirefightAi
  # What a watch asks a model, only when a reading changed and no rule the watch was given decides it: whether the new
  # reading shows it not started, running, done or failed, with each job or step it lists, and once something failed,
  # why, from the logs a watch read.
  # One call with no tools, on the workspace's quick model. The app reads and keeps everything, this only judges text.
  class WatchJudge
    FEATURE = "watch".freeze
    # state is nil when the model gave none it knows, so nothing moves. parts are [name, state] pairs.
    Reading = Data.define(:state, :said, :parts)

    def initialize(workspace, inferable: nil, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    # so_far is where the watch last had it, not started or running.
    def reading(goal:, before:, now:, so_far:)
      content = ask(READING_PROMPT, Schemas::WatchReading,
                    "## The goal\n#{goal}\n\n## Where it was so far\n#{so_far}\n\n## The reading before\n#{before.presence || '(none)'}\n\n## The reading now\n#{now}")
      parts = Array(content[:parts]).filter_map do |part|
        part = part.to_h.with_indifferent_access
        state = part[:state].presence_in(Schemas::WatchReading::PART_STATES)
        [ part[:name].to_s.strip, state ] if part[:name].present? && state
      end
      Reading.new(state: content[:state].presence_in(Schemas::WatchReading::STATES), said: content[:said].to_s.strip, parts: parts)
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
      A person asked to be told when something in a production system is done. You get the goal, where it was so far, the last reading and the new one. Say whether the new reading shows it not begun (not_started), begun and not over (running), the goal reached (done), or something gone wrong such as a failed or crashed state (failed). List each job or step the reading shows with its state.

      - Judge only from the reading. Never guess at what is not in it.
      - A run that exists, is in progress, or has a job or step that started or finished has begun, so it is running unless it is over.
      - When unsure, keep where it was so far.
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
