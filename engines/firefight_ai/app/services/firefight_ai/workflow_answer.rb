module FirefightAi
  # Judges or summarises the data one step of a workflow hands it, in one call with no tools, and answers as fields a
  # later step can branch on: a verdict, a summary and any field the question names. It only reads what it is given.
  class WorkflowAnswer
    FEATURE = "workflow_answer".freeze
    DATA_LIMIT = 24_000
    Answer = Data.define(:verdict, :summary, :fields)

    def initialize(workspace, inferable:)
      @workspace = workspace
      @inferable = inferable
    end

    # fields is a list of [name, description] pairs the answer fills, each a plain value.
    def answer(question:, data:, fields: [])
      asked = [ question.to_s.strip, *fields.map { |name, description| "- #{name}: #{description}" } ].join("\n")
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::INVESTIGATION, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::WorkflowAnswer)
        chat.ask("## The question\n#{asked}\n\n## The data\n#{Evidence.frame('workflow_step', data.to_s.truncate(DATA_LIMIT))}")
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      verdict = Schemas::WorkflowAnswer::VERDICTS.include?(content[:verdict].to_s) ? content[:verdict].to_s : Schemas::WorkflowAnswer::UNSURE
      named = fields.map(&:first)
      given = Array(content[:fields]).filter_map { |field| [ field["name"].to_s, field["value"].to_s.strip ] if named.include?(field["name"].to_s) }.to_h
      Answer.new(verdict: verdict, summary: content[:summary].to_s.strip, fields: named.index_with { |name| given[name].presence })
    end

    PROMPT = <<~PROMPT.freeze
      A step of a workflow a team runs asks you to judge or summarise the data an earlier step read, such as a status, a log search or a metric. Nobody is there to ask, so answer from the data alone.

      - Answer the question the step asks, in two or three plain sentences, naming what in the data shows it.
      - The verdict is ok when the data shows nothing wrong for what was asked, problem when it shows something wrong, and unsure when it cannot tell. Missing or empty data is unsure, never ok.
      - Fill each field the question names from the data, and leave one empty when the data does not show it.
      - #{Evidence::RULE}
      - #{Copy::RULE}
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
