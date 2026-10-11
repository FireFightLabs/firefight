module FirefightAi
  # Halon's small yes or no decisions, such as whether a watched run is done and whether a cited step shows a claim, made
  # one of two ways so the bench can compare them (Configuration#judgments, FIREFIGHT_AI_JUDGMENTS).
  #
  # structured, the default, asks a model for a structured answer, as these decisions always have been. judge asks
  # RubyLLM::Judge, which answers each question with a probability, or a choice with how likely each option is, on the
  # workspace's quick model. Only a model that answers judgments can (the registry's judgment capability, such as
  # OpenAI's decision models). Anthropic, OpenRouter, Bedrock and Gemini answer none, so on any other model a judgment
  # is made the structured way, said once per model in the log, and a decision is never left unmade.
  module Judging
    UNSUPPORTED_EVENT = "ai.judgment_unsupported".freeze
    # Below this the judge is not sure, and nothing moves on its word.
    SURE = 0.5

    @told = Concurrent::Map.new

    # The quick model, when the deployment asked for judgments and the model answers them. Nil means structured.
    def self.choice_for(workspace, mode: nil)
      return nil unless (mode || FirefightAi.configuration.judgments) == Configuration::JUDGMENT_JUDGE

      choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: workspace)
      return choice if judges?(choice)

      @told.compute_if_absent([ choice.provider_name, choice.model ]) do
        Rails.logger.warn({ event: UNSUPPORTED_EVENT, provider: choice.provider_name, model: choice.model }.to_json)
        true
      end
      nil
    end

    def self.judges?(choice)
      RubyLLM.models.find(choice.model.to_s, provider: choice.provider.presence).supports?(:judgment)
    rescue RubyLLM::ModelNotFoundError
      false
    end

    # One judgment on choice, in the ledger and translated like any model call. A workspace's own account that runs dry or
    # refuses its key hands it to the next account, as FirefightAi.generate does.
    def self.judge(choice, inference:, input:, questions:)
      FirefightAi.translating_errors do
        FirefightAi.ensure_paid!(choice)
        begin
          judgment, = Inference.track(inference.merge(choice.ledger)) do
            (choice.context || RubyLLM).judge(input, questions: questions, model: choice.model, provider: choice.provider.presence&.to_sym,
                                                     assume_model_exists: choice.provider.present? && !FirefightAi.registered?(choice.model, choice.provider))
          end
          judgment
        rescue RubyLLM::Error => e
          following = FirefightAi.take_over(choice, e, purpose: AiPurpose::SUMMARY, workspace: inference[:workspace])
          raise unless following && judges?(following)

          choice = following
          retry
        end
      end
    end

    # The option chosen, or nil when the judge was not sure enough of it to move anything.
    def self.sure_choice(answer)
      return nil unless answer

      chosen = answer.choice.to_s
      answer.probabilities.to_h.transform_keys(&:to_s)[chosen].to_f >= SURE ? chosen : nil
    end
  end
end
