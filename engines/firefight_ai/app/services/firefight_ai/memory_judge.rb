module FirefightAi
  # What a new fact about a workspace's setup means for the facts already remembered about the same thing: the same fact
  # in other words, a contradiction, or unrelated. One call with no tools, on the workspace's quick model. The app reads
  # and keeps everything, this only judges text.
  class MemoryJudge
    FEATURE = "memory_check".freeze
    Known = Data.define(:id, :text)
    # verdict is one of Schemas::MemoryVerdicts::VERDICTS.
    Verdict = Data.define(:id, :verdict)

    def initialize(workspace, inferable: nil, member: nil)
      @workspace = workspace
      @inferable = inferable
      @member = member
    end

    # A verdict for each known fact the model judged same or contradicts. A known fact it left out, or gave a verdict it
    # does not know, is unrelated, so a doubtful answer never stops a fact being saved. Any failure, choosing the model
    # included, is raised as a FirefightAi::Error.
    def verdicts(fact:, known:)
      return [] if known.empty?

      numbered = known.each_with_index.to_h { |each, index| [ index + 1, each ] }
      listed = numbered.map { |number, each| "#{number}. #{each.text}" }.join("\n")
      response, = FirefightAi.translating_errors do
        FirefightAi.generate(model_choice, purpose: AiPurpose::SUMMARY, inference: inference_context) do |chat|
          chat.with_instructions(PROMPT)
          chat.with_schema(Schemas::MemoryVerdicts)
          chat.ask("## The new fact\n#{fact}\n\n## Already remembered\n#{listed}")
        end
      end
      Array(parsed(response)[:verdicts]).filter_map do |each|
        each = each.to_h.with_indifferent_access
        judged = numbered[each[:number].to_i]
        verdict = each[:verdict].presence_in(Schemas::MemoryVerdicts::VERDICTS)
        Verdict.new(id: judged.id, verdict: verdict) if judged && verdict && verdict != Schemas::MemoryVerdicts::UNRELATED
      end
    rescue RubyLLM::Error, RubyLLM::ConfigurationError => error
      raise TerminalError.new(error.message, reason: error.class.name.demodulize)
    end

    PROMPT = <<~PROMPT.freeze
      Halon keeps short facts about a team's production setup, such as which database is production or which branch a service deploys from. You get a new fact and the facts already remembered about the same thing, numbered. Judge each remembered fact against the new one.

      - same: both say one thing, in any words. "web deploys from main" and "main is the branch web ships from" are the same.
      - contradicts: both cannot be true at once. "web deploys from main" and "web deploys from the release branch" contradict.
      - unrelated: about something else, or the new fact only adds to it. "web deploys from main" and "web runs two instances" are unrelated.
      - Judge only from the words. When unsure, answer unrelated.
      - Give a verdict for every remembered fact, by its number.
    PROMPT

    private

    def parsed(response) = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, member: @member, prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end
