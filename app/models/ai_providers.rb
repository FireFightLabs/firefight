# The model providers a workspace can add as its own AI account. RubyLLM is the source of what a provider needs. Its
# configuration options say which settings exist and its requirements which must be filled. config/ai_providers.yml
# adds the display name, the recommended models and which providers are offered at all. The only file that reads
# RubyLLM::Provider, so a RubyLLM upgrade that adds a setting reaches the form with no change here.
module AiProviders
  REGISTRY_PATH = Rails.root.join("config/ai_providers.yml")

  KIND_API_KEY = "api_key".freeze
  KIND_OAUTH = "oauth".freeze
  # An AI subscription signed in through the subscription proxy (AiSubscriptions).
  KIND_SUBSCRIPTION = "subscription".freeze

  # Settings that are credentials. They are encrypted, never sent back to the page, and only reach a model through
  # WorkspaceAiAccount#llm_context.
  SECRET_SETTINGS = %w[api_key secret_key session_token service_account_key ai_auth_token].freeze

  # Without these a provider reaches for credentials the server itself holds: Bedrock a credential provider object,
  # Vertex AI the machine's application default credentials. A workspace's account must bring its own.
  EXPLICIT_CREDENTIALS = { "bedrock" => %w[api_key secret_key], "vertexai" => %w[service_account_key] }.freeze

  # Bedrock's Converse API takes smaller images and documents inline than the others.
  INLINE_FILE_LIMITS = { "bedrock" => { Chat::Attachment::KIND_IMAGE => 3.5.megabytes, Chat::Attachment::KIND_PDF => 4.megabytes } }.freeze

  # A setting whose value is an address the server will call.
  ADDRESS_SETTING = "api_base".freeze

  # Settings a provider writes into the host it calls, such as Bedrock's region, so each must be a plain name.
  HOST_NAME_SETTINGS = %w[region location].freeze
  HOST_NAME = /\A[a-z0-9-]+\z/i

  # A workspace's subscriptions answer through the subscription proxy, in OpenAI's shape. It is a provider of its own, so
  # nothing keyed by provider (an account's backups, code fixes, the chat's model picker) takes it for OpenAI and sends
  # the proxy a model without the workspace's prefix. Its models are the workspace's own, which RubyLLM's registry cannot
  # hold, so it takes any id, and SubscriptionProxy::ModelFacts says how large each is.
  SUBSCRIPTION_PROXY = "subscription_proxy".freeze

  class SubscriptionProxyProvider < RubyLLM::Providers::OpenAI
    RubyLLM::Providers::OpenAI.protocols.each { |name, protocol_class| protocols[name] = protocol_class }
    @default_protocol = RubyLLM::Providers::OpenAI.default_protocol

    def api_base = @config.subscription_proxy_api_base

    def headers = { "Authorization" => "Bearer #{@config.subscription_proxy_api_key}" }

    def account_identity = Digest::SHA256.hexdigest([ api_base, @config.subscription_proxy_api_key ].join("\0"))

    class << self
      def configuration_options = %i[subscription_proxy_api_key subscription_proxy_api_base]

      def configuration_requirements = %i[subscription_proxy_api_key subscription_proxy_api_base]

      def assume_models_exist? = true
    end
  end

  # Called once at boot, so every context starts with the proxy's settings emptied too (every_provider_option).
  def self.register_subscription_proxy!
    RubyLLM::Provider.register(SUBSCRIPTION_PROXY.to_sym, SubscriptionProxyProvider)
  end

  # The registry's sections that are not providers.
  SECTIONS = %w[settings chat_models].freeze

  # A model a person can switch a dashboard chat to, with the name and the few words the picker shows.
  ChatModel = Data.define(:model, :label, :note)

  Field = Data.define(:key, :option, :label, :secret, :required)

  # A provider that charges more at busy hours, as a multiple of the price the registry holds. days and hours are in
  # UTC, each hour range from its first hour up to its last, and off_peak_dates are the first and last dates of days
  # charged at the registry's price whatever the hour.
  PeakPricing = Data.define(:multiplier, :days, :hours, :off_peak_dates) do
    def self.from(entry)
      return nil unless entry

      new(multiplier: entry.fetch("multiplier").to_r, days: entry.fetch("days").freeze, hours: entry.fetch("hours").map { |from, to| (from...to) }.freeze,
          off_peak_dates: entry.fetch("off_peak_dates", []).map { |first, last| (Date.iso8601(first)..Date.iso8601(last)) }.freeze)
    end

    def factor(at)
      peak?(at.utc) ? multiplier : 1
    end

    # The last day the off-peak dates are known for, the end of the last year they list. Past it a holiday is priced as
    # any other day, so the next year's dates have to be added before then (RefreshModelRegistryJob says so).
    def dates_known_through = off_peak_dates.empty? ? nil : Date.new(off_peak_dates.map(&:last).max.year, 12, 31)

    private

    def peak?(at)
      days.include?(at.strftime("%A").downcase) && hours.any? { |range| range.cover?(at.hour) } && off_peak_dates.none? { |range| range.cover?(at.to_date) }
    end
  end

  # main_models are the models Halon's loop runs on and fast_models its quick work, preferred first, and backup_models what
  # the loop carries on with when the main one stops answering. The last main and fast model is always in RubyLLM's catalog.
  Provider = Data.define(:slug, :name, :main_models, :fast_models, :backup_models, :code_fix_models, :code_review_models, :fields, :local, :code_fixes, :sign_in, :assumes_models, :peak_pricing) do
    def field(key) = fields.find { |field| field.key == key.to_s }

    def secret_fields = fields.select(&:secret)

    def options = fields.map(&:option)

    # What a call that ran at at costs as a multiple of the registry's price.
    def price_factor(at) = peak_pricing ? peak_pricing.factor(at) : 1

    def recommended(role) = role.to_s == WorkspaceAiAccount::FAST ? fast_model : main_model

    # The first main model the registry holds for this provider with a price and a size, so its cost shows and the loop
    # can make room in it. Falls back to the last, which the catalog RubyLLM ships always holds.
    def main_model = first_ready(main_models, fallback: main_models.last) { |model| loop_ready?(model) }

    # The quick model, the first of fast_models_ready. A quick model needs only a price.
    def fast_model = fast_models_ready.first

    # The quick models tried in turn when the provider says one is not there for the account. Each is a model, or several
    # read like main_models: the first the registry prices, else the last, which the catalog RubyLLM ships holds.
    def fast_models_ready = fast_models.map { |entry| resolve_fast(entry) }.uniq

    def resolve_fast(entry) = first_ready(Array(entry), fallback: Array(entry).last) { |model| FirefightAi.priced_for?(model, slug) }

    # The backups the loop tries in turn. Each is a model, or several read like main_models, and counts while the registry
    # can price and size it. A provider with no backup of its own carries on with its main model, since what failed was
    # another provider or another model.
    def backup_models_ready
      ready = backup_models.filter_map { |entry| first_ready(Array(entry)) { |model| loop_ready?(model) } }.uniq
      ready.presence || [ main_model ].compact.select { |model| loop_ready?(model) }
    end

    # The first of models that ready accepts, else fallback. A model listed ahead of the one used was passed over, and
    # AiProviders.passed_over says so, so a newer model the registry does not hold yet never gives way to an older one
    # unseen.
    def first_ready(models, fallback: nil, &ready)
      chosen = models.find(&ready) || fallback
      AiProviders.passed_over(slug, models, chosen)
      chosen
    end

    def loop_ready?(model) = FirefightAi.priced_for?(model, slug) && FirefightAi.context_window(model, provider: slug).present?

    # The recommended model for the role while the registry can price it for this provider, and size it for the main
    # loop, or nil.
    def ready(role)
      model = recommended(role)
      return nil unless model && FirefightAi.priced_for?(model, slug)
      return model if role.to_s == WorkspaceAiAccount::FAST

      model if FirefightAi.context_window(model, provider: slug)
    end

    # The first model this provider recommends for writing code fixes that the registry holds for it with a price, so a
    # code fix's budget can be counted. Nil otherwise, and a code fix runs on the next best model.
    def code_fix_model_ready = code_fix_models.find { |model| FirefightAi.priced_for?(model, slug) }

    # The same for the model that reviews a code fix's change, which is charged to the same budget.
    def code_review_model_ready = code_review_models.find { |model| FirefightAi.priced_for?(model, slug) }

    # RubyLLM's own check on a configuration built from this provider's settings, for what the requirements alone do not
    # say, such as Azure taking a key or a token.
    def configured?(config) = RubyLLM::Provider.resolve!(slug).configured?(config)

    # The chat models the registry knows for this provider, for the form to pick from. Empty for a provider whose models
    # are the customer's own names, such as an Azure deployment.
    def chat_models
      return [] if assumes_models

      RubyLLM.models.by_provider(slug.to_sym).chat_models.reject(&:unlisted?).map(&:id).sort
    end
  end

  # Every address is read from the environment when it is asked for, so nothing about the endpoint is assumed.
  SignIn = Data.define(:label, :env) do
    def client_id = ENV[env.fetch("client_id_env")].presence

    def authorize_url = ENV[env.fetch("authorize_url_env")].presence

    def token_url = ENV[env.fetch("token_url_env")].presence

    def api_base = ENV[env.fetch("api_base_env")].presence

    def scopes = ENV[env.fetch("scopes_env")].to_s.split(/[\s,]+/).compact_blank

    def configured? = [ client_id, authorize_url, token_url, api_base ].all?(&:present?)
  end

  # How long a passed over model is not named again, and no refresh asked for again, for one provider.
  PASSED_OVER_QUIET = 1.hour

  def self.all = offered.values

  # Names the models listed ahead of used that the registry could not offer for the provider, at most once in
  # PASSED_OVER_QUIET for each, and asks for the registry to be refreshed, at most once in PASSED_OVER_QUIET in all. A new
  # database gets here, since RubyLLM fills an empty registry table from the catalog its gem shipped with, which can be
  # older than the models listed here, and until a refresh brings the newer ones in the older ones are used.
  def self.passed_over(slug, models, used)
    wanted = models.take_while { |model| model != used }
    return if wanted.empty?
    return unless quiet_once("ai_providers/passed_over/#{slug}/#{wanted.join(',')}")

    Rails.logger.warn({ event: "ai.model_passed_over", provider: slug, wanted: wanted, used: used }.to_json)
    RefreshModelRegistryJob.perform_later if quiet_once("ai_providers/registry_refresh_asked")
  end

  def self.quiet_once(key) = Rails.cache.write(key, true, expires_in: PASSED_OVER_QUIET, unless_exist: true)
  private_class_method :quiet_once

  def self.offered
    @offered ||= registry.except(*SECTIONS).to_h do |slug, entry|
      [ slug, build(slug, entry) ]
    end.freeze
  end

  def self.find(slug) = offered[slug.to_s]

  # What a call to the provider that ran at at costs as a multiple of the registry's price, 1 for a provider that is
  # not offered or charges the same at every hour.
  def self.price_factor(slug, at: Time.current) = find(slug)&.price_factor(at) || 1

  # What a workspace may add. A local provider runs on a private network, which only an install someone runs
  # themselves reaches.
  def self.for_workspace(workspace)
    private_allowed = Entitlements.private_ai_endpoints?(workspace)
    all.reject { |provider| provider.local && !private_allowed }
  end

  # Every setting any offered provider asks for, the only ones a form may send.
  def self.setting_keys = all.flat_map { |provider| provider.fields.map(&:key) }.uniq

  # The most a provider takes inline of each kind of file, where it takes less than Chat::Attachment::MAX_BYTES.
  def self.inline_file_limits(provider) = INLINE_FILE_LIMITS.fetch(provider.to_s, {})

  def self.offered_to?(workspace, slug) = for_workspace(workspace).any? { |provider| provider.slug == slug.to_s }

  # Every setting RubyLLM declares for any provider, so a context can start with all of them empty.
  def self.every_provider_option
    RubyLLM::Provider.providers.values.flat_map(&:configuration_options).uniq
  end

  def self.local_slugs = RubyLLM::Provider.local_providers.keys.map(&:to_s)

  # The models a dashboard chat on this provider can switch to, in the registry's order, each only while the registry holds
  # it for the provider with a price and a size, so a chat on it is billed and can make room in its window.
  def self.chat_models(slug)
    listed_chat_models(slug).select do |entry|
      FirefightAi.priced_for?(entry.model, slug) && FirefightAi.context_window(entry.model, provider: slug)
    end
  end

  # What people are told a model is called, by the picker's name, else the registry's, else the id.
  def self.model_label(slug, model) = chat_model_label(slug, model) || FirefightAi.model_name(model, provider: slug) || model.to_s

  # The name the picker gives a model this provider serves, or nil for a model it does not list.
  def self.chat_model_label(slug, model) = listed_chat_models(slug).find { |entry| entry.model == model.to_s }&.label

  def self.listed_chat_models(slug)
    @listed_chat_models ||= registry.fetch("chat_models", {}).to_h do |provider, entries|
      [ provider, entries.map { |entry| ChatModel.new(model: entry.fetch("model"), label: entry.fetch("label"), note: entry.fetch("note")) }.freeze ]
    end.freeze
    @listed_chat_models.fetch(slug.to_s, [])
  end
  private_class_method :listed_chat_models

  # The model the deployment's own keys write code fixes with when nothing names one. It is the first provider in the
  # registry's order that recommends one for code, holds a key here and can price it. Nil leaves code fixes on the
  # investigation's model.
  def self.deployment_code_fix_choice(config = RubyLLM.config) = deployment_code_choice(:code_fix_model_ready, config)

  # The model the deployment's own keys review a code fix's change with when nothing names one, read the same way.
  def self.deployment_code_review_choice(config = RubyLLM.config) = deployment_code_choice(:code_review_model_ready, config)

  def self.deployment_code_choice(pick, config)
    all.each do |provider|
      model = provider.public_send(pick)
      return FirefightAi::ModelChoice.new(model: model, provider: provider.slug) if model && provider.configured?(config)
    end
    nil
  end
  private_class_method :deployment_code_choice

  # The model the deployment's own keys run a role on when no env var names one. It is the recommended main or quick
  # model of the first provider in the registry's order that holds a key here and whose model the registry prices. prefer is tried
  # first, so quick work stays with the provider the main loop runs on. Nil when no provider qualifies.
  def self.deployment_choice(role, prefer: nil, config: RubyLLM.config)
    candidates = all.partition { |provider| provider.slug == prefer.to_s }.flatten
    candidates.each do |provider|
      next unless provider.configured?(config)

      model = provider.ready(role)
      return FirefightAi::ModelChoice.new(model: model, provider: provider.slug) if model
    end
    nil
  end

  # What the deployment's own keys can carry Halon's loop on when failing stops answering, in the order to try them.
  # Other providers come first, since an outage usually takes a whole provider. The failing provider's own backups come
  # last, where they are other models, since an outage can be one model's.
  def self.deployment_backup_choices(failing, config: RubyLLM.config)
    others, same = all.partition { |provider| provider.slug != failing.provider_name }
    (others + same).select { |provider| provider.configured?(config) }.flat_map do |provider|
      provider.backup_models_ready.filter_map do |model|
        next if provider.slug == failing.provider_name && model == failing.model

        FirefightAi::ModelChoice.new(model: model, provider: provider.slug)
      end
    end
  end

  # What quick work carries on with when the provider says failing's model is not there for the account: the next quick
  # model of its provider after it, on the same account and payer, such as Gemini on a Vertex AI project without Claude
  # enabled. Nil when the provider has none left, or when the model is not one of its quick models, since a model an
  # admin picked is theirs to change.
  def self.quick_fallback(failing, tried: [])
    provider = find(failing.provider_name)
    at = provider&.fast_models&.index { |entry| Array(entry).include?(failing.model) }
    return nil unless at

    gone = tried.map(&:model) + [ failing.model ]
    following = provider.fast_models.drop(at + 1).filter_map { |entry| provider.resolve_fast(entry) }.find { |model| gone.exclude?(model) }
    following && failing.with(model: following)
  end

  # The models a workspace's own account carries Halon's loop on when its model failed, before any other account: the
  # backups of the account's provider that are not the model that failed. The account and its payer stay the same.
  def self.account_backup_choices(failing)
    provider = find(failing.provider_name)
    return [] unless provider

    (provider.backup_models_ready - [ failing.model ]).map { |model| failing.with(model: model) }
  end

  # The ChatGPT sign in seam, when the flag is on and every address it needs is set. Nil otherwise.
  def self.sign_in_for(workspace)
    return nil unless FeatureFlags.enabled?(workspace, FeatureFlags::CHATGPT_SIGN_IN)

    offered.values.find { |provider| provider.sign_in&.configured? }
  end

  def self.build(slug, entry)
    klass = RubyLLM::Provider.resolve!(slug)
    labels = registry.fetch("settings").merge(entry.fetch("labels", {}))
    required = klass.configuration_requirements.map(&:to_s) + EXPLICIT_CREDENTIALS.fetch(slug, []).map { |key| "#{slug}_#{key}" }
    fields = klass.configuration_options.filter_map do |option|
      key = option.to_s.delete_prefix("#{slug}_")
      next unless labels.key?(key)

      Field.new(key: key, option: option, label: labels.fetch(key), secret: SECRET_SETTINGS.include?(key), required: required.include?(option.to_s))
    end
    Provider.new(
      slug: slug, name: entry.fetch("name"), main_models: Array(entry["main"]).freeze, fast_models: Array(entry["fast"]).freeze, backup_models: Array(entry["backup"]).freeze, code_fix_models: code_models(slug, entry, "code_fix"),
      code_review_models: code_models(slug, entry, "code_review"), fields: fields.freeze,
      local: klass.local?, code_fixes: FirefightAi::ModelProxy.supported?(slug), sign_in: sign_in(entry["sign_in"]),
      assumes_models: klass.assume_models_exist?, peak_pricing: PeakPricing.from(entry["peak_pricing"])
    )
  end
  private_class_method :build

  # ANTHROPIC_CODE_FIX_MODEL, ANTHROPIC_CODE_REVIEW_MODEL and the like replace the registry's picks for that provider's
  # accounts, since each provider names the same model its own way.
  def self.code_models(slug, entry, key) = Array(ENV["#{slug.upcase}_#{key.upcase}_MODEL"].presence || entry[key]).freeze
  private_class_method :code_models

  def self.sign_in(entry)
    return nil unless entry

    SignIn.new(label: entry.fetch("label"), env: entry.except("label").freeze)
  end
  private_class_method :sign_in

  def self.registry = @registry ||= YAML.load_file(REGISTRY_PATH)
  private_class_method :registry
end
