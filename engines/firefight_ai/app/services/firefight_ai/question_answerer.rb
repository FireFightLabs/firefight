module FirefightAi
  # Answers a coding agent's question from what Halon already knows about the change, the person's own words and what
  # was read, before the person is asked. One call with no tools. It answers only what that material settles, and a
  # question it cannot settle goes to the person rather than to a guess.
  class QuestionAnswerer
    FEATURE = "code_question".freeze
    PART_LIMIT = 16_000
    # option is the label of the option the answer picks, nil for an answer in words.
    Reply = Data.define(:text, :option)

    def initialize(workspace, inferable: nil)
      @workspace = workspace
      @inferable = inferable
    end

    # The answer, or nil when the material does not settle it. options are [label, consequence] pairs, recommended the
    # agent's pick and why.
    def answer(question:, known:, options: [], recommended: nil)
      asked = [ question.to_s, *options.map { |label, consequence| "- #{label}: #{consequence}" }, ("Recommended: #{recommended}" if recommended) ].compact.join("\n")
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::INVESTIGATION, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::QuestionAnswer)
        chat.ask("## What is known about the change\n#{known.to_s.strip.truncate(PART_LIMIT).presence || '(nothing)'}\n\n" \
                 "## The coding agent's question and its options\n#{Evidence.frame('coding_agent', asked)}")
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      text = content[:answer].to_s.strip
      return unless content[:answered] == true && text.present?

      Reply.new(text: text, option: options.map(&:first).find { |label| label.casecmp?(content[:option].to_s.strip) })
    end

    PROMPT = <<~PROMPT.freeze
      A coding agent writing a code change for a person asked a question. You get what is known about the change, the person's own words and what was read of the systems involved, and the question.

      - Answer only when the person's words or the evidence settle it, and say where the answer comes from.
      - When the question offers options, pick the one the person's words or the way the code already behaves elsewhere settle, by its label, whether or not it is the one recommended.
      - When it is a choice only the person can make, or the material does not show it, do not answer, so the person is asked.
      - Never answer from what is usual or likely. A wrong answer here becomes a wrong change.
      - #{Evidence::RULE}
      - #{Punctuation::RULE}
    PROMPT

    private

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, prompt_template: FEATURE, prompt_version: Prompt.version(PROMPT), prompt_text: PROMPT
      }
    end
  end
end
