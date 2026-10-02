require "ruby_llm"
require "schematist"
require "firefight_ai/version"
require "firefight_ai/configuration"
require "firefight_ai/errors"
require "firefight_ai/prompt"
require "firefight_ai/engine"

module FirefightAi
  extend self

  def configuration
    @configuration ||= Configuration.new
  end

  def configure
    yield configuration
  end

  # A provider only travels with a model the registry cannot place, Bedrock or Ollama.
  ModelChoice = Data.define(:model, :provider) do
    def provider_name
      Inference.provider_for(model, provider: provider)
    end
  end

  # Resolved at call time, this file loads before the autoloader knows AiPurpose.
  def env_prefix(purpose)
    {
      AiPurpose::POSTMORTEM => "POSTMORTEM_AI",
      AiPurpose::INCIDENT_RESPONSE => "INCIDENT_AI",
      AiPurpose::SUMMARY => "SUMMARY_AI",
      AiPurpose::MILESTONES => "MILESTONES_AI",
      AiPurpose::INVESTIGATION => "INVESTIGATION_AI",
      AiPurpose::CITATION_CHECK => "CITATION_CHECK_AI",
      AiPurpose::LESSONS => "LESSONS_AI",
      AiPurpose::CODE_FIX => "CODE_FIX_AI",
      AiPurpose::EMBEDDING => "EMBEDDING_AI"
    }.fetch(purpose)
  end

  def fallback_model(purpose)
    {
      AiPurpose::POSTMORTEM => "gpt-4o",
      AiPurpose::INCIDENT_RESPONSE => "gpt-4o-mini",
      AiPurpose::SUMMARY => "gpt-4o-mini",
      AiPurpose::MILESTONES => "gpt-4o-mini",
      AiPurpose::INVESTIGATION => "gpt-4o",
      AiPurpose::CODE_FIX => "gpt-4o",
      AiPurpose::EMBEDDING => "text-embedding-3-small"
    }.fetch(purpose)
  end

  # Most specific first, workspace override for the purpose, for any purpose, the
  # purpose's env var, then the parent purpose's model when it has one, the deployment default, the fallback.
  def model_for(purpose, workspace: nil)
    override = workspace && workspace.ai_model_overrides.for_purpose(purpose).min_by { |row| row.purpose == purpose ? 0 : 1 }
    return ModelChoice.new(model: override.model, provider: override.provider.presence) if override

    prefix = env_prefix(purpose)
    if ENV["#{prefix}_MODEL"].present?
      return ModelChoice.new(model: ENV["#{prefix}_MODEL"], provider: ENV["#{prefix}_PROVIDER"].presence)
    end

    parent = AiPurpose::PARENTS[purpose]
    return model_for(parent, workspace: workspace) if parent
    if configuration.default_model.present?
      return ModelChoice.new(model: configuration.default_model, provider: configuration.default_provider.presence)
    end

    ModelChoice.new(model: fallback_model(purpose), provider: nil)
  end

  # The models table is the registry once it holds a row, and only a refresh puts anything in it.
  def refresh_models!
    RubyLLM.models.refresh.all.size
  end

  # A model whose price the registry does not know is billed at zero, so nothing stops a run that uses it.
  def priced?(model_id)
    model = RubyLLM.models.all.find { |candidate| candidate.id == model_id.to_s }
    return false unless model

    text = model.pricing.text_tokens
    text.input.to_f.positive? && text.output.to_f.positive?
  rescue StandardError
    false
  end

  # What a call cost in millionths of a dollar, from the registry's price per million tokens. Zero for a model it
  # cannot price, the same as priced? says.
  def cost_micros(model_id, input:, output:, cache_read: 0)
    text = RubyLLM.models.find(model_id.to_s).pricing.text_tokens
    cached = text.respond_to?(:cached_input) && text.cached_input.to_f.positive? ? text.cached_input.to_f : text.input.to_f
    ((input - cache_read) * text.input.to_f + cache_read * cached + output * text.output.to_f).round
  rescue StandardError
    0
  end

  # How much the model can read at once, from the registry. Nil when it is not known, and nothing
  # is assumed in its place, since a wrong number fails a run halfway through.
  def context_window(model_id)
    window = RubyLLM.models.find(model_id.to_s).context_window.to_i
    window.positive? ? window : nil
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  # A model the registry does not know needs its provider named. RubyLLM then trusts the id.
  def chat(choice)
    return RubyLLM.chat(model: choice.model) if choice.provider.blank?

    RubyLLM.chat(model: choice.model, provider: choice.provider, assume_model_exists: !registered?(choice.model))
  end

  # One vector per call, tracked like every other model call. The dimensions are fixed by the
  # column, so a model that answers with a different width is a configuration error, not a result.
  def embed(text, workspace:, inferable: nil)
    choice = model_for(AiPurpose::EMBEDDING)
    embedding, = translating_errors do
      Inference.track(
        workspace: workspace, feature: "embedding", provider: choice.provider_name,
        model: choice.model, inferable: inferable
      ) do
        RubyLLM.embed(text, model: choice.model, provider: choice.provider&.to_sym)
      end
    end
    embedding
  end

  # Every vector in a workspace has to come from this one, so a search ignores rows written by
  # anything else.
  def embedding_model = model_for(AiPurpose::EMBEDDING).model

  def registered?(model)
    RubyLLM.models.find(model)
    true
  rescue RubyLLM::ModelNotFoundError
    false
  end
end
