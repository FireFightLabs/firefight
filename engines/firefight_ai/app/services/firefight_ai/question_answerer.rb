module FirefightAi
  # Answers a coding agent's question from what Halon already knows about the change, the person's own words and what
  # was read, before the person is asked. One call with no tools. It answers only what that material settles, and a
  # question it cannot settle goes to the person rather than to a guess.
  class QuestionAnswerer
    FEATURE = "code_question".freeze
    PART_LIMIT = 16_000

    def initialize(workspace, inferable: nil)
      @workspace = workspace
      @inferable = inferable
    end

    # The answer, or nil when the material does not settle it.
    def answer(question:, known:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::INVESTIGATION, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::QuestionAnswer)
        chat.ask("## What is known about the change\n#{known.to_s.strip.truncate(PART_LIMIT).presence || '(nothing)'}\n\n" \
                 "## The coding agent's question\n#{Evidence.frame('coding_agent', question.to_s)}")
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      content[:answer].to_s.strip.presence if content[:answered] == true
    end

    PROMPT = <<~PROMPT.freeze
      A coding agent writing a code change for a person asked a question. You get what is known about the change, the person's own words and what was read of the systems involved, and the question.

      - Answer only when the person's words or the evidence settle it, and say where the answer comes from.
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
