require "ruby_llm"
require "schematist"
require "firefight_ai/version"
require "firefight_ai/configuration"
require "firefight_ai/credit"
require "firefight_ai/balance"
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

  # A provider only travels with a model the registry cannot place, Bedrock or Ollama, or with a workspace's own account.
  # context is the RubyLLM::Context holding that account's settings, nil for the deployment's own. payer is who pays
  # (AiPayer), nil for a call made on the deployment's account with no workspace choosing, such as a rehearsal.
  ModelChoice = Data.define(:model, :provider, :context, :payer) do
    def initialize(model:, provider: nil, context: nil, payer: nil) = super

    def provider_name
      Inference.provider_for(model, provider: provider)
    end

    # What the ledger records about who ran the call and who paid.
    def ledger = { provider: provider_name, model: model, **(payer ? payer.ledger : {}) }

    # Nobody can pay, so no call is made.
    def unpaid? = payer.present? && payer.nobody?

    def own_account? = payer.present? && payer.own_account?
  end

  # Said for a call nobody can pay for, which every caller turns into AiCredit's words.
  NO_PAYER = "No AI account can pay for this call.".freeze

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
      AiPurpose::INCIDENT_RESPONSE => "gpt-4o-mini",
      AiPurpose::SUMMARY => "gpt-4o-mini",
      AiPurpose::MILESTONES => "gpt-4o-mini",
      AiPurpose::INVESTIGATION => "gpt-4o",
      AiPurpose::EMBEDDING => "text-embedding-3-small"
    }.fetch(purpose)
  end

  # How much one call for a purpose may write. A provider that refuses for credit is never asked again with less, since
  # an answer cut to fit a balance is worse than a clean failure that tells the team.
  OutputCap = Data.define(:max)

  # A provider reserves the whole cap against the balance before it writes a word, and with no cap it reserves the
  # model's own maximum, so each purpose asks for what it writes plus room for the model's reasoning. Read from the
  # ledger: an agent turn wrote at most about 5,200 tokens, a citation check about 1,500, the rest under 1,000.
  def output_caps
    {
      AiPurpose::INVESTIGATION => 16_000,
      AiPurpose::POSTMORTEM => 16_000,
      AiPurpose::CITATION_CHECK => 8_000,
      AiPurpose::LESSONS => 8_000,
      AiPurpose::CODE_FIX => 8_000,
      AiPurpose::INCIDENT_RESPONSE => 4_000,
      AiPurpose::SUMMARY => 4_000,
      AiPurpose::MILESTONES => 4_000
    }
  end

  # The purpose's env var sets the maximum, as its model is set. A purpose never takes its parent's, since what it
  # writes is its own even on its parent's model. Never above what the registry says the model can write, as the
  # choice's provider serves it.
  def output_cap(purpose, choice:)
    max = ENV["#{env_prefix(purpose)}_MAX_OUTPUT_TOKENS"].presence&.to_i || output_caps.fetch(purpose)
    OutputCap.new(max: [ max, max_output_tokens(choice.model, provider: choice.provider) ].compact.min)
  end

  # What the registry says the model can write in one answer. Nil when it is not known. One id can be several
  # providers' with different limits, so the provider is named when it is known.
  def max_output_tokens(model_id, provider: nil)
    limit = RubyLLM.models.find(model_id.to_s, provider: provider.presence).max_output_tokens.to_i
    limit.positive? ? limit : nil
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  # One model call for a purpose, in the ledger and capped at what the purpose writes. The block gets a fresh chat
  # each time. Returns the response and its ledger row, as Inference.track does. A workspace's own account that runs
  # dry or refuses its key hands the call to the next one in its order, which is asked afresh. Any other refusal fails
  # the call.
  def generate(choice, purpose:, inference:)
    translating_errors do
      ensure_paid!(choice)
      begin
        limit = output_cap(purpose, choice: choice).max
        Inference.track(inference.merge(choice.ledger, max_output_tokens: limit)) { yield chat(choice).with_max_output_tokens(limit) }
      rescue RubyLLM::Error => e
        choice = take_over(choice, e, purpose: purpose, workspace: inference[:workspace])
        raise unless choice

        retry
      end
    end
  end

  def ensure_paid!(choice)
    raise OutOfCredit, NO_PAYER if choice.unpaid?
  end

  # The payer is out from this call on, which the app records once, however many calls are refused.
  def refused_for_good(choice, error)
    return unless error.is_a?(RubyLLM::Error)

    configuration.on_refused&.call(choice.payer, choice.provider_name, error)
  end

  # A call refused for good is recorded against whoever paid. When the workspace's own account ran dry or refused its
  # key, the next one in its order carries on, and the choice to carry on with is answered. Nil when the refusal is
  # not one another account could help with. With nobody left the call is out of credit, which says where to fix it.
  def take_over(choice, error, purpose:, workspace:)
    refused_for_good(choice, error)
    return nil unless choice.own_account? && AiPayer.gives_way?(error)

    following = model_for(purpose, workspace: workspace)
    raise OutOfCredit, error.message if following.unpaid? || following.payer == choice.payer

    following
  end

  # The model and payer a call for the purpose runs on now: the workspace's first account that can pay (AiFunding).
  # When nobody can, the deployment's model with nobody paying, so a caller can still read what the model is, and the
  # call itself is refused as out of credit.
  def model_for(purpose, workspace: nil)
    choices_for(purpose, workspace: workspace).first || deployment_model_for(purpose, workspace: workspace).with(payer: AiPayer::NOBODY)
  end

  # Every choice in the order they are tried.
  def choices_for(purpose, workspace: nil) = AiFunding.for(workspace, purpose)

  # The deployment's own model for the purpose, most specific first: workspace override for the purpose, for any
  # purpose, the purpose's env var, the model the providers recommend for it, then the parent purpose's model when it
  # has one, the deployment default, the fallback.
  def deployment_model_for(purpose, workspace: nil)
    override = workspace && workspace.ai_model_overrides.for_purpose(purpose).min_by { |row| row.purpose == purpose ? 0 : 1 }
    return ModelChoice.new(model: override.model, provider: override.provider.presence) if override

    prefix = env_prefix(purpose)
    if ENV["#{prefix}_MODEL"].present?
      return ModelChoice.new(model: ENV["#{prefix}_MODEL"], provider: ENV["#{prefix}_PROVIDER"].presence)
    end

    recommended = recommended_model_for(purpose)
    return recommended if recommended

    parent = AiPurpose::PARENTS[purpose]
    return deployment_model_for(parent, workspace: workspace) if parent
    if configuration.default_model.present?
      return ModelChoice.new(model: configuration.default_model, provider: configuration.default_provider.presence)
    end

    ModelChoice.new(model: fallback_model(purpose), provider: nil)
  end

  # Code fixes run on the model the providers recommend for writing code, when nothing names one for them and this
  # deployment holds a key that reaches it. Every other purpose has none of its own.
  def recommended_model_for(purpose)
    AiProviders.deployment_code_fix_choice if purpose == AiPurpose::CODE_FIX
  end

  # Points a saved chat at the choice, its model and the context holding its account's settings, so a chat resumed after
  # the payer changed carries on with the new one. The context is never saved, so every job binds it after loading.
  def bind(chat, choice)
    chat.with_context(choice.context)
    return chat if chat.model_id.to_s == choice.model && (choice.provider.blank? || chat.provider.to_s == choice.provider.to_s)

    chat.with_model(choice.model, provider: choice.provider, assume_model_exists: choice.provider.present? && !registered?(choice.model, choice.provider))
  end

  # The models table is the registry once it holds a row, and only a refresh puts anything in it.
  def refresh_models!
    RubyLLM.models.refresh.all.size
  end

  # A model whose price the registry does not know is billed at zero, so nothing stops a run that uses it.
  def priced?(model_id)
    priced_model?(RubyLLM.models.all.find { |candidate| candidate.id == model_id.to_s })
  end

  # The same for the model as one provider serves it, since a model id can be several providers' with different prices.
  def priced_for?(model_id, provider)
    priced_model?(RubyLLM.models.all.find { |candidate| candidate.id == model_id.to_s && candidate.provider.to_s == provider.to_s })
  end

  def priced_model?(model)
    return false unless model

    text = model.pricing.text_tokens
    text.input.to_f.positive? && text.output.to_f.positive?
  rescue StandardError
    false
  end

  # The chat models a run can be told to use, those the registry can price, so a run on one is never billed at zero.
  def priced_chat_models
    RubyLLM.models.chat_models.select { |model| priced_model?(model) }
  end

  # What a call cost in millionths of a dollar, priced by RubyLLM itself for the model as its provider serves it, since
  # one id can be several providers' at different prices. input is every input token, cache reads and writes included,
  # and each kind is charged at its own price, a cache read at the cache read price. A kind the registry has no price for
  # is charged as plain input. Zero for a model it cannot price, the same as priced_for? says.
  def cost_micros(model_id, provider:, input:, output:, cache_read: 0, cache_write: 0)
    model = RubyLLM.models.find(model_id.to_s, provider: provider.presence)
    plain = [ input - cache_read - cache_write, 0 ].max
    total = model.cost_for(RubyLLM::Tokens.new(input: plain, output: output, cache_read: cache_read, cache_write: cache_write)).total
    total ||= model.cost_for(RubyLLM::Tokens.new(input: input, output: output)).total
    (total.to_f * 1_000_000).round
  rescue RubyLLM::ModelNotFoundError
    0
  end

  # How much the model can read at once, from the registry, as the provider serves it when one is named. Nil when it is
  # not known, and nothing is assumed in its place, since a wrong number fails a run halfway through.
  def context_window(model_id, provider: nil)
    window = RubyLLM.models.find(model_id.to_s, provider: provider.presence).context_window.to_i
    window.positive? ? window : nil
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  # What the registry says a model takes besides text, such as image or pdf. A model it does not know takes only text,
  # since nothing is assumed in its place. The provider matters, since one id can be listed under several providers
  # that take different things, and without it the registry picks one by its own preference.
  def input_modalities(model_id, provider: nil)
    RubyLLM.models.find(model_id.to_s, provider: provider.presence).modalities.input
  rescue RubyLLM::ModelNotFoundError
    []
  end

  # A model the registry does not know needs its provider named. RubyLLM then trusts the id. A workspace's own account
  # runs in its own context, so nothing of the deployment's configuration reaches it.
  def chat(choice)
    llm = choice.context || RubyLLM
    return llm.chat(model: choice.model) if choice.provider.blank?

    llm.chat(model: choice.model, provider: choice.provider, assume_model_exists: !registered?(choice.model, choice.provider))
  end

  # One vector per call, tracked like every other model call. The dimensions are fixed by the
  # column, so a model that answers with a different width is a configuration error, not a result.
  # Always the deployment's model and account, whoever pays for the rest, since every vector in a workspace has to come
  # from the same model.
  def embed(text, workspace:, inferable: nil)
    choice = deployment_model_for(AiPurpose::EMBEDDING)
    embedding, = translating_errors do
      Inference.track(workspace: workspace, feature: Inference::FEATURE_EMBEDDING, inferable: inferable, **choice.ledger) do
        RubyLLM.embed(text, model: choice.model, provider: choice.provider&.to_sym)
      end
    rescue RubyLLM::Error => e
      refused_for_good(choice, e)
      raise
    end
    embedding
  end

  # Many vectors in one call, for text that serves every workspace at once, such as the providers' documentation in the
  # docs store. Run on the deployment's own model and account, and recorded with no workspace. Answers the vectors in
  # the order of texts, and the model that wrote them.
  def embed_documents(texts)
    choice = deployment_model_for(AiPurpose::EMBEDDING)
    embedding, = translating_errors do
      Inference.track(workspace: nil, feature: Inference::FEATURE_PROVIDER_DOCS, **choice.ledger.merge(AiPayer.deployment_only.ledger)) do
        RubyLLM.embed(texts, model: choice.model, provider: choice.provider&.to_sym)
      end
    rescue RubyLLM::ConfigurationError => e
      raise TerminalError.new(e.message, reason: e.class.name.demodulize)
    end
    vectors = embedding.vectors
    [ vectors.first.is_a?(Numeric) ? [ vectors ] : vectors, choice.model ]
  end

  # Every vector in a workspace has to come from this one, so a search ignores rows written by
  # anything else.
  def embedding_model = deployment_model_for(AiPurpose::EMBEDDING).model

  ACCOUNT_CHECK = "ai_account_check".freeze
  ACCOUNT_CHECK_PROMPT = "Reply with the word ready.".freeze
  ACCOUNT_CHECK_TOKENS = 16

  # One tiny call on the account's quick model, to show its key works before Halon relies on it. Ledgered like any other
  # call. Raises what the provider answered, translated, so the app can say it in plain words.
  def check_account(choice, workspace:)
    translating_errors do
      Inference.track(workspace: workspace, feature: ACCOUNT_CHECK, max_output_tokens: ACCOUNT_CHECK_TOKENS, **choice.ledger) do
        chat(choice).with_max_output_tokens(ACCOUNT_CHECK_TOKENS).ask(ACCOUNT_CHECK_PROMPT)
      end
    end
  end

  # Whether the registry lists the model, under the provider when one is named, since RubyLLM resolves a named
  # provider's model only from that provider's listing.
  def registered?(model, provider = nil)
    RubyLLM.models.find(model.to_s, provider: provider.presence)
    true
  rescue RubyLLM::ModelNotFoundError
    false
  end
end
