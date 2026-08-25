require "ruby_llm"
require "ruby_llm/schema"
require "firefight_ai/version"
require "firefight_ai/configuration"
require "firefight_ai/errors"
require "firefight_ai/engine"

module FirefightAi
  extend self

  def configuration
    @configuration ||= Configuration.new
  end

  def configure
    yield configuration
  end

  # What a purpose runs on. A provider only travels with a model the registry
  # cannot place on its own (a Bedrock or Ollama deployment).
  ModelChoice = Data.define(:model, :provider) do
    def provider_name
      Inference.provider_for(model, provider: provider)
    end
  end

  # Resolved at call time: this file loads before the host's autoloader
  # knows AiPurpose.
  def env_prefix(purpose)
    {
      AiPurpose::POSTMORTEM => "POSTMORTEM_AI",
      AiPurpose::INCIDENT_RESPONSE => "INCIDENT_AI",
      AiPurpose::SUMMARY => "SUMMARY_AI"
    }.fetch(purpose)
  end

  def fallback_model(purpose)
    {
      AiPurpose::POSTMORTEM => "gpt-4o",
      AiPurpose::INCIDENT_RESPONSE => "gpt-4o-mini",
      AiPurpose::SUMMARY => "gpt-4o-mini"
    }.fetch(purpose)
  end

  # Every service resolves its model here, most specific first: the
  # workspace's override for the purpose, the workspace's override for every
  # purpose, the purpose's env var, the deployment default, the built-in
  # fallback.
  def model_for(purpose, workspace: nil)
    override = workspace && workspace.ai_model_overrides.for_purpose(purpose).min_by { |row| row.purpose == purpose ? 0 : 1 }
    return ModelChoice.new(model: override.model, provider: override.provider.presence) if override

    prefix = env_prefix(purpose)
    if ENV["#{prefix}_MODEL"].present?
      return ModelChoice.new(model: ENV["#{prefix}_MODEL"], provider: ENV["#{prefix}_PROVIDER"].presence)
    end
    if configuration.default_model.present?
      return ModelChoice.new(model: configuration.default_model, provider: configuration.default_provider.presence)
    end

    ModelChoice.new(model: fallback_model(purpose), provider: nil)
  end

  # A chat on the chosen model. A model the registry does not know needs its
  # provider named, and RubyLLM then trusts the id as given.
  def chat(choice)
    return RubyLLM.chat(model: choice.model) if choice.provider.blank?

    RubyLLM.chat(model: choice.model, provider: choice.provider, assume_model_exists: !registered?(choice.model))
  end

  def registered?(model)
    RubyLLM.models.find(model)
    true
  rescue RubyLLM::ModelNotFoundError
    false
  end
end
