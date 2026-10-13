module FirefightAi
  # Reads why one step of a workflow failed and suggests a change to that step's settings when they caused it, such as a
  # resource named wrongly or an argument the tool does not take. One call with no tools. It suggests nothing for a
  # failure its settings did not cause, so a person is never handed a guess.
  class WorkflowRepair
    FEATURE = "workflow_repair".freeze
    PART_LIMIT = 8_000
    Suggestion = Data.define(:reason, :config)

    def initialize(workspace, inferable:)
      @workspace = workspace
      @inferable = inferable
    end

    # step is the failed step's kind, name and settings as a hash. Returns a Suggestion, or nil when it has none.
    def suggest(workflow_name:, step:, error:, kind_words:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::INVESTIGATION, inference: inference_context) do |chat|
        chat.with_instructions(PROMPT)
        chat.with_schema(Schemas::WorkflowRepair)
        chat.ask("## The workflow\n#{workflow_name}\n\n## The step that failed\n#{kind_words}\n#{JSON.pretty_generate(step).truncate(PART_LIMIT)}\n\n" \
                 "## Why it failed\n#{Evidence.frame('workflow_run', error.to_s.truncate(PART_LIMIT))}")
      end
      content = response.parsed.is_a?(Hash) ? response.parsed.with_indifferent_access : {}
      return unless content[:fixable] == true && content[:reason].present?

      config = JSON.parse(content[:config_json].to_s)
      config.is_a?(Hash) && config.any? ? Suggestion.new(reason: content[:reason].to_s.strip, config: config) : nil
    rescue JSON::ParserError
      nil
    end

    PROMPT = <<~PROMPT.freeze
      A step of a workflow a team runs failed. You get the step's kind and settings and why it failed. Suggest a change to that step's settings only when the settings caused the failure, such as a resource or channel named wrongly, an argument the tool does not take, or a question that cannot be answered from the data it is given.

      - Change only what caused it, and keep every other setting as it is.
      - Suggest nothing for an outage, a timeout, a provider that was down, a refused permission, an approval nobody gave, or anything else changing the settings would not fix.
      - A reference such as {{steps.check.data}} reads an earlier step's output, so keep it unless it names something that is not there.
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
