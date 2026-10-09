module FirefightAi
  # Whether a replayed answer names the same cause as an answer the team rated, so a regression run can tell a case it
  # still gets right from one it now gets wrong. One call with no tools, on Firefight's own model, never a workspace's.
  class AnswerJudge
    FEATURE = "regression_judge".freeze

    Verdict = Data.define(:verdict, :reason)

    def initialize(workspace, inferable:)
      @workspace = workspace
      @inferable = inferable
    end

    # rated and replayed are each the answer's text, its summary with the cause it gave.
    def judge(rated:, replayed:)
      response, = FirefightAi.generate(model_choice, purpose: AiPurpose::CITATION_CHECK, inference: inference_context) do |chat|
        chat.with_instructions(system_prompt)
        chat.with_schema(Schemas::SameCause)
        chat.ask("## The first answer\n#{rated}\n\n## The second answer\n#{replayed}")
      end
      verdict(response.parsed)
    end

    private

    def verdict(content)
      content = content.is_a?(Hash) ? content.with_indifferent_access : {}
      said = content[:verdict].presence_in([ Schemas::SameCause::SAME, Schemas::SameCause::DIFFERENT, Schemas::SameCause::UNCLEAR ])
      Verdict.new(verdict: said || Schemas::SameCause::UNCLEAR, reason: content[:reason].to_s.strip)
    end

    def inference_context
      {
        workspace: @workspace, feature: FEATURE, provider: model_choice.provider_name, model: model_choice.model,
        inferable: @inferable, prompt_template: FEATURE, prompt_version: Prompt.version(system_prompt), prompt_text: system_prompt
      }
    end

    def model_choice = @model_choice ||= FirefightAi.model_for(AiPurpose::CITATION_CHECK)

    def system_prompt
      <<~PROMPT
        Two answers were given to the same production incident. Say whether they name the same cause.

        - Same means they blame the same thing going wrong, even in other words or with different detail. A different service, change, resource or failure is a different cause.
        - One answer naming a cause and the other naming none, or both naming none, is unclear.
        - Judge only the cause, never which answer is better written or more complete.
        - #{Copy::RULE}
      PROMPT
    end
  end
end
