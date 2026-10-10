# The bench pays with keys of its own, never the app's. A bench run once drained the key live chats ran on, and a chat
# then failed. Each model call a bench run makes, Halon's and the judge's, runs with the key named HALON_BENCH_ and the
# provider (HALON_BENCH_OPENROUTER_API_KEY for a model through OpenRouter), on a configuration that starts with every
# provider setting empty, so the app's own keys can never ride along. A run without that key refuses to start.
module Conversation::BenchKeys
  PREFIX = "HALON_BENCH_".freeze
  SUFFIX = "_API_KEY".freeze
  # The model the judge grades with, and its provider, when set. Without them the judge uses the model the app checks
  # citations with, still on the bench's key.
  JUDGE_MODEL = "HALON_BENCH_JUDGE_MODEL".freeze
  JUDGE_PROVIDER = "HALON_BENCH_JUDGE_PROVIDER".freeze

  class Missing < StandardError; end

  module_function

  def env_name(provider) = "#{PREFIX}#{provider.to_s.upcase}#{SUFFIX}"

  # Whether any bench key is set, for a page that cannot know the model yet.
  def any? = ENV.any? { |name, value| name.start_with?(PREFIX) && name.end_with?(SUFFIX) && value.present? }

  # The model on the bench's key for its provider. Raises Missing, naming the variable, when that key is not set.
  def choice(model:, provider: nil)
    provider = provider.presence || Inference.provider_for(model)
    key = ENV[env_name(provider)].presence
    raise Missing, "The bench pays with its own key, never the app's. Set #{env_name(provider)} to run #{model}." unless key

    account = WorkspaceAiAccount.new(provider: provider, kind: AiProviders::KIND_API_KEY)
    field = account.provider_definition&.secret_fields&.first
    raise Missing, "The bench cannot run #{model}, since Firefight does not offer #{provider} as an AI provider." unless field

    account.assign_settings(field.key => key)
    FirefightAi::ModelChoice.new(model: model, provider: provider, context: account.llm_context)
  end

  def judge
    model = ENV[JUDGE_MODEL].presence
    return choice(model: model, provider: ENV[JUDGE_PROVIDER].presence) if model

    deployed = FirefightAi.deployment_model_for(AiPurpose::CITATION_CHECK)
    choice(model: deployed.model, provider: deployed.provider_name)
  end
end
