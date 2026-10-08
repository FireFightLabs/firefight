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
      AiPurpose::CODE_FIX => "gpt-4o",
      AiPurpose::EMBEDDING => "text-embedding-3-small"
    }.fetch(purpose)
  end

  # How much one call for a purpose may write, and the least still worth asking for when the account can pay for less.
  OutputCap = Data.define(:max, :floor) do
    # The cap to try once more after the provider refused for credit and named what it can still pay for. Nil when it
    # named nothing, or too little for a useful answer.
    def after_refusal(error, tried)
      affordable = Credit.from(error).affordable
      affordable if affordable && affordable >= floor && affordable < tried
    end
  end

  # A provider reserves the whole cap against the balance before it writes a word, and with no cap it reserves the
  # model's own maximum, so each purpose asks for what it writes plus room for the model's reasoning. Read from the
  # ledger: an agent turn wrote at most about 5,200 tokens, a citation check about 1,500, the rest under 1,000. Each
  # floor is what a full answer of that kind has needed, so a reply cut shorter is never asked for.
  def output_caps
    {
      AiPurpose::INVESTIGATION => [ 16_000, 4_000 ],
      AiPurpose::POSTMORTEM => [ 16_000, 6_000 ],
      AiPurpose::CITATION_CHECK => [ 8_000, 2_000 ],
      AiPurpose::LESSONS => [ 8_000, 2_000 ],
      AiPurpose::INCIDENT_RESPONSE => [ 4_000, 1_000 ],
      AiPurpose::SUMMARY => [ 4_000, 1_000 ],
      AiPurpose::MILESTONES => [ 4_000, 1_000 ]
    }
  end

  # The purpose's env var sets the maximum, as its model is set. A purpose never takes its parent's, since what it
  # writes is its own even on its parent's model. Never above what the registry says the model can write.
  def output_cap(purpose, model:)
    built_in_max, floor = output_caps.fetch(purpose)
    max = ENV["#{env_prefix(purpose)}_MAX_OUTPUT_TOKENS"].presence&.to_i || built_in_max
    max = [ max, max_output_tokens(model) ].compact.min
    OutputCap.new(max: max, floor: [ floor, max ].min)
  end

  # What the registry says the model can write in one answer. Nil when it is not known.
  def max_output_tokens(model_id)
    limit = RubyLLM.models.find(model_id.to_s).max_output_tokens.to_i
    limit.positive? ? limit : nil
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  # One model call for a purpose, in the ledger and capped at what the purpose writes. A provider that refuses for
  # credit and names an output it can still pay for is asked once more with that, when it still fits a useful answer.
  # The block gets a fresh chat each time. Returns the response and its ledger row, as Inference.track does.
  # A workspace's own account that runs dry or refuses its key hands the call to the next one in its order, which is
  # asked afresh.
  def generate(choice, purpose:, inference:)
    translating_errors do
      ensure_paid!(choice)
      cap = output_cap(purpose, model: choice.model)
      limit = cap.max
      retried = false
      begin
        Inference.track(inference.merge(choice.ledger, max_output_tokens: limit)) { yield chat(choice).with_max_output_tokens(limit) }
      rescue RubyLLM::Error => e
        smaller = retried ? nil : cap.after_refusal(e, limit)
        unless smaller
          choice = take_over(choice, e, purpose: purpose, workspace: inference[:workspace])
          raise unless choice

          cap = output_cap(purpose, model: choice.model)
          limit = cap.max
          retried = false
          retry
        end

        note_short_of_credit(inference[:feature], limit, smaller)
        limit = smaller
        retried = true
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
    return choice.payer.refused!(error) if choice.own_account?

    AiAccount.ran_out!(choice.provider_name) if Credit.from(error).out_of_credit?
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

  def note_short_of_credit(feature, asked, affordable)
    Rails.logger.warn({ event: "ai.short_of_credit", feature: feature, asked: asked, affordable: affordable }.to_json)
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
  # purpose, the purpose's env var, then the parent purpose's model when it has one, the deployment default, the fallback.
  def deployment_model_for(purpose, workspace: nil)
    override = workspace && workspace.ai_model_overrides.for_purpose(purpose).min_by { |row| row.purpose == purpose ? 0 : 1 }
    return ModelChoice.new(model: override.model, provider: override.provider.presence) if override

    prefix = env_prefix(purpose)
    if ENV["#{prefix}_MODEL"].present?
      return ModelChoice.new(model: ENV["#{prefix}_MODEL"], provider: ENV["#{prefix}_PROVIDER"].presence)
    end

    parent = AiPurpose::PARENTS[purpose]
    return deployment_model_for(parent, workspace: workspace) if parent
    if configuration.default_model.present?
      return ModelChoice.new(model: configuration.default_model, provider: configuration.default_provider.presence)
    end

    ModelChoice.new(model: fallback_model(purpose), provider: nil)
  end

  # Points a saved chat at the choice, its model and the context holding its account's settings, so a chat resumed after
  # the payer changed carries on with the new one. The context is never saved, so every job binds it after loading.
  def bind(chat, choice)
    chat.with_context(choice.context)
    return chat if chat.model_id.to_s == choice.model && (choice.provider.blank? || chat.provider.to_s == choice.provider.to_s)

    chat.with_model(choice.model, provider: choice.provider, assume_model_exists: choice.provider.present? && !registered?(choice.model))
  end

  # The models table is the registry once it holds a row, and only a refresh puts anything in it.
  def refresh_models!
    RubyLLM.models.refresh.all.size
  end

  # A model whose price the registry does not know is billed at zero, so nothing stops a run that uses it.
  def priced?(model_id)
    priced_model?(RubyLLM.models.all.find { |candidate| candidate.id == model_id.to_s })
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

    llm.chat(model: choice.model, provider: choice.provider, assume_model_exists: !registered?(choice.model))
  end

  # One vector per call, tracked like every other model call. The dimensions are fixed by the
  # column, so a model that answers with a different width is a configuration error, not a result.
  # Always the deployment's model and account, whoever pays for the rest, since every vector in a workspace has to come
  # from the same model.
  def embed(text, workspace:, inferable: nil)
    choice = deployment_model_for(AiPurpose::EMBEDDING)
    embedding, = translating_errors do
      Inference.track(workspace: workspace, feature: "embedding", inferable: inferable, **choice.ledger) do
        RubyLLM.embed(text, model: choice.model, provider: choice.provider&.to_sym)
      end
    rescue RubyLLM::Error => e
      refused_for_good(choice, e)
      raise
    end
    embedding
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

  def registered?(model)
    RubyLLM.models.find(model)
    true
  rescue RubyLLM::ModelNotFoundError
    false
  end
end
