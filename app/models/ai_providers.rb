# The model providers a workspace can add as its own AI account. RubyLLM is the source of what a provider needs. Its
# configuration options say which settings exist and its requirements which must be filled. config/ai_providers.yml
# adds the display name, the recommended models and which providers are offered at all. The only file that reads
# RubyLLM::Provider, so a RubyLLM upgrade that adds a setting reaches the form with no change here.
module AiProviders
  REGISTRY_PATH = Rails.root.join("config/ai_providers.yml")

  KIND_API_KEY = "api_key".freeze
  KIND_OAUTH = "oauth".freeze

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

  Field = Data.define(:key, :option, :label, :secret, :required)

  # main_models are the models Halon's loop runs on, preferred first, and backup_models what it carries on with when the
  # main one stops answering. The last of each is always in RubyLLM's catalog.
  Provider = Data.define(:slug, :name, :main_models, :fast_model, :backup_models, :code_fix_model, :fields, :local, :code_fixes, :sign_in, :assumes_models) do
    def field(key) = fields.find { |field| field.key == key.to_s }

    def secret_fields = fields.select(&:secret)

    def options = fields.map(&:option)

    def recommended(role) = role.to_s == WorkspaceAiAccount::FAST ? fast_model : main_model

    # The first main model the registry holds for this provider with a price and a size, so its cost shows and the loop
    # can make room in it. Falls back to the last, which the catalog RubyLLM ships always holds.
    def main_model = main_models.find { |model| loop_ready?(model) } || main_models.last

    # The backup the loop carries on with, while the registry can price and size it. A provider with no backup of its own
    # carries on with its main model, since what failed was another provider or another model.
    def backup_model
      model = backup_models.find { |candidate| loop_ready?(candidate) } || main_model
      model if loop_ready?(model)
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

    # The model this provider recommends for code fixes, while the registry holds it for this provider with a price, so
    # a code fix's budget can be counted. Nil otherwise, and a code fix runs on the next best model.
    def code_fix_model_ready = (code_fix_model if code_fix_model && FirefightAi.priced_for?(code_fix_model, slug))

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

  def self.all = offered.values

  def self.offered
    @offered ||= registry.except("settings").to_h do |slug, entry|
      [ slug, build(slug, entry) ]
    end.freeze
  end

  def self.find(slug) = offered[slug.to_s]

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

  # The model the deployment's own keys write code fixes with when nothing names one. It is the first provider in the
  # registry's order that recommends one for code, holds a key here and can price it. Nil leaves code fixes on the
  # investigation's model.
  def self.deployment_code_fix_choice(config = RubyLLM.config)
    all.each do |provider|
      model = provider.code_fix_model_ready
      return FirefightAi::ModelChoice.new(model: model, provider: provider.slug) if model && provider.configured?(config)
    end
    nil
  end

  # The model the deployment's own keys run a role on when no env var names one. It is the recommended main or quick
  # model of the first provider in the registry's order that holds a key here and whose model the registry prices. prefer is tried
  # first, so quick work stays with the provider the main loop runs on. Nil when no provider qualifies.
  def self.deployment_choice(role, prefer: nil, config: RubyLLM.config)
    candidates = all.partition { |provider| provider.slug == prefer.to_s }.flatten
    candidates.each do |provider|
      model = provider.ready(role)
      return FirefightAi::ModelChoice.new(model: model, provider: provider.slug) if model && provider.configured?(config)
    end
    nil
  end

  # What the deployment's own keys can carry Halon's loop on when failing stops answering, in the order to try them.
  # Other providers come first, since an outage usually takes a whole provider. The failing provider's own backup comes
  # last, where it is another model, since an outage can be one model's.
  def self.deployment_backup_choices(failing, config: RubyLLM.config)
    others, same = all.partition { |provider| provider.slug != failing.provider_name }
    (others + same).filter_map do |provider|
      model = provider.backup_model
      next unless model && provider.configured?(config)
      next if provider.slug == failing.provider_name && model == failing.model

      FirefightAi::ModelChoice.new(model: model, provider: provider.slug)
    end
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
      slug: slug, name: entry.fetch("name"), main_models: Array(entry["main"]).freeze, fast_model: entry["fast"], backup_models: Array(entry["backup"]).freeze, code_fix_model: code_fix_model(slug, entry), fields: fields.freeze,
      local: klass.local?, code_fixes: FirefightAi::ModelProxy.supported?(slug), sign_in: sign_in(entry["sign_in"]),
      assumes_models: klass.assume_models_exist?
    )
  end
  private_class_method :build

  # ANTHROPIC_CODE_FIX_MODEL and the like replace the registry's pick for that provider's accounts, since each
  # provider names the same model its own way.
  def self.code_fix_model(slug, entry) = ENV["#{slug.upcase}_CODE_FIX_MODEL"].presence || entry["code_fix"]
  private_class_method :code_fix_model

  def self.sign_in(entry)
    return nil unless entry

    SignIn.new(label: entry.fetch("label"), env: entry.except("label").freeze)
  end
  private_class_method :sign_in

  def self.registry = @registry ||= YAML.load_file(REGISTRY_PATH)
  private_class_method :registry
end
