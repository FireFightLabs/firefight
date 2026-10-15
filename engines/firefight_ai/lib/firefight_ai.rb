require "concurrent/map"
require "ruby_llm"
require "schematist"
require "firefight_ai/version"
require "firefight_ai/configuration"
require "firefight_ai/credit"
require "firefight_ai/balance"
require "firefight_ai/errors"
require "firefight_ai/prompt"
require "firefight_ai/http_adapter"
require "firefight_ai/tracing"
require "firefight_ai/tool_search"
require "firefight_ai/request_id"
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
      AiPurpose::CODE_REVIEW => "CODE_REVIEW_AI",
      AiPurpose::HELPER => "HELPER_AI",
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
      AiPurpose::CODE_REVIEW => 8_000,
      AiPurpose::HELPER => 8_000,
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
  # dry or refuses its key hands the call to the next one in its order, which is asked afresh. Quick work whose model is
  # not there for the account carries on with the provider's next quick model. Any other refusal fails the call.
  def generate(choice, purpose:, inference:)
    tried = []
    translating_errors do
      ensure_paid!(choice)
      begin
        limit = output_cap(purpose, choice: choice).max
        Inference.track(inference.merge(choice.ledger, max_output_tokens: limit)) { yield chat(choice).with_max_output_tokens(limit) }
      rescue RubyLLM::Error => e
        tried << choice
        choice = take_over(choice, e, purpose: purpose, workspace: inference[:workspace]) || quick_fallback(choice, e, purpose: purpose, tried: tried)
        raise unless choice

        retry
      end
    end
  end

  # The provider's next quick model on the same account, when quick work's model is not there for the account, such as
  # Claude on a Vertex AI project that has not enabled it. Nil for any other purpose or refusal.
  def quick_fallback(choice, error, purpose:, tried: [])
    return nil unless AiPurpose.quick?(purpose) && model_unavailable?(error)

    AiProviders.quick_fallback(choice, tried: tried)
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

  # What the loop carries on with when the provider behind choice stopped answering, or nil when nothing can.
  def backup_for(choice, purpose:, workspace:, tried: [])
    AiFunding.backup_for(workspace, purpose, failing: choice, tried: tried)
  end

  # The model and payer a call for the purpose runs on now: the workspace's first account that can pay (AiFunding).
  # When nobody can, the deployment's model with nobody paying, so a caller can still read what the model is, and the
  # call itself is refused as out of credit.
  def model_for(purpose, workspace: nil)
    choices_for(purpose, workspace: workspace).first || deployment_model_for(purpose, workspace: workspace).with(payer: AiPayer::NOBODY)
  end

  # Every choice in the order they are tried.
  def choices_for(purpose, workspace: nil) = AiFunding.for(workspace, purpose)

  # The model a code fix's change is reviewed on, paid by whoever paid for writing it, since the review is charged to the
  # change's own budget. The change's own model when that payer has no review model of its own.
  def review_choice_for(writing, workspace:)
    choices_for(AiPurpose::CODE_REVIEW, workspace: workspace).find { |choice| choice.payer == writing.payer } || writing
  end

  # The deployment's own model for the purpose, most specific first: workspace override for the purpose, for any
  # purpose, the purpose's env var, the model the providers recommend for it, then the parent purpose's model when it
  # has one. After that it depends on the purpose's tier. Halon's own loop takes FIREFIGHT_AI_MODEL, then the main
  # model of FIREFIGHT_AI_PROVIDER when it is set and holds a key, else of the first provider this deployment holds a key for. A side job takes FIREFIGHT_AI_QUICK_MODEL, then the
  # quick model of the provider the loop runs on, then FIREFIGHT_AI_MODEL. Both end at the purpose's fallback.
  def deployment_model_for(purpose, workspace: nil)
    override = workspace&.ai_model_override_for(purpose)
    return ModelChoice.new(model: override.model, provider: override.provider.presence) if override

    prefix = env_prefix(purpose)
    if ENV["#{prefix}_MODEL"].present?
      return ModelChoice.new(model: ENV["#{prefix}_MODEL"], provider: ENV["#{prefix}_PROVIDER"].presence)
    end

    recommended = recommended_model_for(purpose, workspace)
    return recommended if recommended

    parent = AiPurpose::PARENTS[purpose]
    return deployment_model_for(parent, workspace: workspace) if parent
    return quick_deployment_model(purpose, workspace) if AiPurpose.quick?(purpose)

    default = default_choice
    return default if default
    return AiProviders.deployment_choice(WorkspaceAiAccount::MAIN, prefer: configuration.default_provider) || fallback_choice(purpose) if purpose == AiPurpose::INVESTIGATION

    fallback_choice(purpose)
  end

  # A side job stays with the provider the loop runs on where it recommends a quick model, so one key covers both.
  def quick_deployment_model(purpose, workspace)
    return ModelChoice.new(model: configuration.quick_model, provider: configuration.quick_provider) if configuration.quick_model.present?

    main = deployment_model_for(AiPurpose::INVESTIGATION, workspace: workspace)
    AiProviders.deployment_choice(WorkspaceAiAccount::FAST, prefer: main.provider_name) || default_choice || fallback_choice(purpose)
  end

  def default_choice
    ModelChoice.new(model: configuration.default_model, provider: configuration.default_provider.presence) if configuration.default_model.present?
  end

  def fallback_choice(purpose) = ModelChoice.new(model: fallback_model(purpose), provider: nil)

  # Code fixes are written on the model the providers recommend for writing code and reviewed on the one they recommend
  # for reviewing it, when nothing names one and this deployment holds a key that reaches it. A model named for code
  # fixes is left to review them too, as it did before the review had a model of its own. Every other purpose has none.
  def recommended_model_for(purpose, workspace = nil)
    case purpose
    when AiPurpose::CODE_FIX then AiProviders.deployment_code_fix_choice
    when AiPurpose::CODE_REVIEW then AiProviders.deployment_code_review_choice unless named_for?(AiPurpose::CODE_FIX, workspace)
    end
  end

  # Whether an override or the purpose's env var names its model, rather than a recommendation or its parent.
  def named_for?(purpose, workspace)
    ENV["#{env_prefix(purpose)}_MODEL"].present? || (workspace.present? && workspace.ai_model_override_named_for?(purpose))
  end

  # Points a saved chat at the choice, its model and the context holding its account's settings, so a chat resumed after
  # the payer changed carries on with the new one. The context is never saved, so every job binds it after loading.
  def bind(chat, choice)
    same = chat.model_id.to_s == choice.model && (choice.provider.blank? || chat.provider.to_s == choice.provider.to_s)
    rebind_context(chat, choice.context, moving: !same)
    unless same
      chat.with_model(choice.model, provider: choice.provider, assume_model_exists: choice.provider.present? && !registered?(choice.model, choice.provider))
    end
    name_session(chat)
  end

  # The provider that routes each call of a chat to one of several hosts, and keeps a chat's calls on the host whose
  # cache holds what it read when every call names the chat's session.
  SESSION_ROUTER = "openrouter".freeze

  # The session is the saved chat's own id, which holds nothing secret or personal. Without it OpenRouter keys the route
  # on the chat's opening messages and moves a chat whose opening changed to another host, which has read none of it.
  # Any other provider is sent nothing, and a chat moved off OpenRouter by a backup stops sending it.
  def name_session(chat)
    chat.with_provider_options(chat.provider.to_s == SESSION_ROUTER ? { session_id: chat.id.to_s } : nil)
  end

  # RubyLLM resolves the chat's current model again under the new context, which a context holding only another
  # provider's settings refuses, as when one workspace account hands over to another on a different provider. The new
  # settings are in place by then, and the model the chat moves to is resolved under them next, so only a chat staying
  # on its model needs them to hold its provider.
  def rebind_context(chat, context, moving:)
    chat.with_context(context)
  rescue RubyLLM::ConfigurationError
    raise unless moving
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
  # and each kind is charged at its own price, a cache read at the cache read price. cache_write_by_ttl splits the cache
  # writes by how long they last, such as { "1h" => 2048 }, and a provider that charges more for a longer lifetime, as
  # Anthropic charges twice the input price for an hour, has each part priced at its own rate. A kind the registry has no
  # price for is charged as plain input. Zero for a model it cannot price, the same as priced_for? says.
  def cost_micros(model_id, provider:, input:, output:, cache_read: 0, cache_write: 0, cache_write_by_ttl: nil)
    model = RubyLLM.models.find(model_id.to_s, provider: provider.presence)
    plain = [ input - cache_read - cache_write, 0 ].max
    tokens = RubyLLM::Tokens.new(input: plain, output: output, cache_read: cache_read, cache_write: cache_write, cache_write_by_ttl: cache_write_by_ttl)
    total = model.cost_for(tokens).total
    total ||= model.cost_for(RubyLLM::Tokens.new(input: input, output: output)).total
    (total.to_f * 1_000_000).round
  rescue RubyLLM::ModelNotFoundError
    0
  end

  # How much the model can read at once, from the registry, as the provider serves it when one is named. Nil when it is
  # not known, and nothing is assumed in its place, since a wrong number fails a run halfway through.
  # The temperature Halon's own loop is sent on this model, or nil to send none: when the deployment set none, or the
  # registry says the model takes no temperature, as a reasoning model such as o3 does.
  def loop_temperature(choice)
    temperature = configuration.loop_temperature
    return nil if temperature.nil?
    return nil if RubyLLM.models.find(choice.model.to_s, provider: choice.provider.presence).metadata[:temperature] == false

    temperature
  rescue RubyLLM::ModelNotFoundError
    temperature
  end

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

  # The name the registry gives a model, such as Claude Sonnet 5, or nil for a model it does not know.
  def model_name(model_id, provider: nil)
    RubyLLM.models.find(model_id.to_s, provider: provider.presence).name.presence
  rescue RubyLLM::ModelNotFoundError
    nil
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

  # Whether the provider behind choice searches deferred tools itself (ToolSearch), unless the deployment turned it off.
  def tool_search?(choice) = configuration.tool_search != false && ToolSearch.native?(choice)

  # Characters of a tool definition to a token, a little under what models count, so an estimate errs high.
  TOOL_CHARS_PER_TOKEN = 3.5

  # Whether tools are small enough to hold whole from the start of a chat on a provider without tool search
  # (Configuration#held_tools_budget). Counting stops once past the budget, so a large catalog is not read through.
  def fits_up_front?(tools)
    left = configuration.held_tools_budget * TOOL_CHARS_PER_TOKEN
    tools.each do |tool|
      left -= tool.name.to_s.size + tool.description.to_s.size + tool.parameters_schema.to_json.size
      return false if left.negative?
    end
    true
  end

  # Whether definitions this many characters long in all, each counted as fits_up_front? counts it, fit the same budget.
  def chars_fit_up_front?(chars) = chars <= configuration.held_tools_budget * TOOL_CHARS_PER_TOKEN

  # How long a boundary a person's next message reads from lasts: an hour, the longest a provider keeps one, so a reply
  # after a pause reads the history rather than writing all of it again (AgentLoop hold_history).
  CACHE_BETWEEN_TURNS = "1h".freeze

  ANTHROPIC = "anthropic".freeze
  # How OpenRouter names Anthropic's models, by their maker.
  ANTHROPIC_ON_ROUTER = "anthropic/".freeze

  # Whether the provider keeps a boundary for CACHE_BETWEEN_TURNS: Anthropic's own API, and OpenRouter for Anthropic's
  # models, which hands the lifetime on to the host serving the call. Anywhere else a boundary keeps the provider's default.
  def lasting_cache?(choice)
    provider = choice.provider_name.to_s
    provider == ANTHROPIC || (provider == SESSION_ROUTER && choice.model.to_s.start_with?(ANTHROPIC_ON_ROUTER))
  end

  # Sets a saved chat up for an agent's turn on choice. The instructions end in a cache boundary, so the tool definitions
  # in front of them and the instructions themselves are read from the provider's cache on every turn after the first.
  # A boundary keeps the provider's default lifetime, five minutes, since a run's calls follow each other within seconds
  # and a write that lasts an hour costs twice the input price rather than one and a quarter. A chat a person comes back
  # to after a pause holds its instructions and the start of each turn for longer (AgentLoop hold_history). tools are
  # handed over whole. deferred_tools are handed over for the provider to search, and only where it does (ToolSearch),
  # since anywhere else they would arrive whole. rolling also asks the provider to cache the conversation as it grows,
  # which a chat resent on every turn needs.
  def ready_chat(chat, choice:, instructions:, tools:, deferred_tools: [], rolling: true)
    bind(chat, choice)
    chat.with_instructions(instructions, cache_until_here: true)
    chat.with_tools(*tools)
    defer_tools(chat, deferred_tools, choice)
    chat.with_caching if rolling
    chat
  end

  # A tool the chat already holds whole stays whole.
  def defer_tools(chat, tools, choice)
    return if tools.empty?

    held = chat.to_llm.tools.keys - chat.to_llm.deferred_tools.keys
    deferred = tools.reject { |tool| held.include?(tool.name.to_sym) }
    chat.with_tools(*deferred, defer: true) if deferred.any? && tool_search?(choice)
  end

  # A chat that moved to a provider without tool search would get every deferred tool in its context whole, so those are
  # taken off, and the chat finds them with open_tools as any chat on that provider does. The rest keep their place.
  def present_tools(chat, choice)
    llm = chat.to_llm
    deferred = llm.deferred_tools
    return if deferred.empty? || tool_search?(choice)

    kept = llm.tools.except(*deferred.keys).values
    llm.with_tools(nil)
    llm.with_tools(*kept, defer: false)
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
