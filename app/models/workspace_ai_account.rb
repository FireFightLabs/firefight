# A workspace's own account with a model provider, which Halon uses before anything the deployment pays with. Accounts
# are tried in their order, and one that runs out of credit or has its key refused is skipped until a check shows it
# works again. Credentials are write-only. They are encrypted here, never serialized, and reach a model only through
# llm_context, which starts from a configuration with every provider setting empty.
class WorkspaceAiAccount < ApplicationRecord
  include Positioned

  MAIN = "main".freeze
  FAST = "fast".freeze
  ROLES = [ MAIN, FAST ].freeze
  KINDS = [ AiProviders::KIND_API_KEY, AiProviders::KIND_OAUTH, AiProviders::KIND_SUBSCRIPTION ].freeze

  LABEL_LIMIT = 80
  ERROR_LIMIT = 300
  HINT_LENGTH = 4

  # The Faraday adapter registered for it in config/initializers/firefight_ai.rb.
  PUBLIC_ADDRESS_ADAPTER = :firefight_public_address

  NOTICE_OUT_OF_CREDIT = "out_of_credit".freeze
  NOTICE_KEY_REFUSED = "key_refused".freeze

  belongs_to :workspace
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true

  encrypts :credentials

  validates :label, presence: true, length: { maximum: LABEL_LIMIT }
  validates :kind, inclusion: { in: KINDS }
  validate :provider_offered
  validate :settings_complete
  validate :models_known
  validate :address_allowed
  validate :host_names_plain

  scope :enabled, -> { where(enabled: true) }
  # Out of credit or refused accounts wait for a check that shows they work again, so a call never waits on them.
  scope :usable, -> { enabled.where(out_of_credit_since: nil, failing_since: nil) }
  scope :stuck, -> { enabled.where.not(out_of_credit_since: nil).or(enabled.where.not(failing_since: nil)) }

  def self.create_in_order!(workspace, attributes)
    account = new(workspace: workspace, **attributes)
    account.save_in_position!
    account
  end

  scope :subscriptions, -> { where(kind: AiProviders::KIND_SUBSCRIPTION) }

  # A subscription's provider is its key in config/ai_subscriptions.yml, so it has no provider definition.
  def provider_definition = (AiProviders.find(provider) unless subscription?)

  def oauth? = kind == AiProviders::KIND_OAUTH

  def subscription? = kind == AiProviders::KIND_SUBSCRIPTION

  def subscription_definition = (AiSubscriptions.find(provider) if subscription?)

  # Whether a call can be made on it now: a provider Firefight offers, or a subscription the proxy holds while the proxy
  # is up and keeps workspaces apart.
  def callable?
    return provider_definition.present? unless subscription?

    subscription_definition.present? && proxy_credential.present? && SubscriptionProxy.usable?
  end

  # The models the subscription's sign-in serves, as the proxy last listed them, each a hash with its id, name,
  # context_window, max_output_tokens and input_modalities.
  def proxy_models = Array(proxy_state.to_h["models"])

  def proxy_model_ids = proxy_models.map { |model| model["id"].to_s }

  # "ChatGPT subscription for ana@example.com", what toasts call it.
  def subscription_named
    named = "#{subscription_definition&.name || provider} subscription"
    credential_hint.present? ? "#{named} for #{credential_hint}" : named
  end

  # How much of its limit is left and when it resets, as the proxy last saw it (SubscriptionProxy::Accounts).
  def proxy_limit = proxy_state.to_h["limit"].to_h

  # The proxy says the sign-in no longer works, so it needs signing in again.
  def signed_out? = subscription? && (failing_since.present? || proxy_state.to_h["signed_out"] == true)

  def limit_reached? = subscription? && proxy_limit["reached_until"].present? && Time.zone.parse(proxy_limit["reached_until"].to_s) > Time.current

  # Blank values keep what is stored, since the form never shows a stored secret and an empty field means unchanged.
  def assign_settings(values)
    definition = provider_definition
    return unless definition

    values = values.to_h.stringify_keys
    kept_secrets = secrets
    kept_settings = settings.to_h.dup
    definition.fields.each do |field|
      next unless values.key?(field.key)

      value = values[field.key].to_s.strip
      if field.secret
        kept_secrets[field.key] = value if value.present?
      else
        value.present? ? kept_settings[field.key] = value : kept_settings.delete(field.key)
      end
    end
    self.settings = kept_settings
    write_secrets(kept_secrets)
  end

  # What the OAuth sign in got: the tokens and when they expire.
  def assign_tokens(tokens, expires_at:)
    write_secrets(secrets.merge(tokens.to_h.stringify_keys))
    self.credentials_expire_at = expires_at
  end

  def store_tokens!(tokens, expires_at:)
    assign_tokens(tokens, expires_at: expires_at)
    save!
  end

  def token(name) = secrets[name.to_s]

  def assign_models(values)
    values = values.to_h.stringify_keys.slice(*ROLES).transform_values { |model| model.to_s.strip }.compact_blank
    self.models = values
  end

  def model_for(role)
    chosen = models.to_h[role.to_s].presence
    return chosen if chosen
    return subscription_definition&.recommended(role, proxy_model_ids) if subscription?

    provider_definition&.recommended(role)
  end

  # The configuration a call on this account runs with. It starts with every setting of every provider RubyLLM knows
  # empty, so nothing the deployment configured, such as Firefight's own keys or a credential provider, can reach a call
  # this account pays for, then takes only this account's settings.
  # A subscription calls the subscription proxy with its client key, the only setting it takes, and names its models with
  # the workspace's prefix (choice_for), so the proxy answers it only from this workspace's sign-ins.
  def llm_context
    definition = provider_definition
    values = context_values
    RubyLLM.context do |config|
      AiProviders.every_provider_option.each { |option| config.public_send("#{option}=", nil) }
      definition&.fields&.each { |field| config.public_send("#{field.option}=", values[field.key]) }
      if subscription?
        config.subscription_proxy_api_key = SubscriptionProxy.settings.client_key
        config.subscription_proxy_api_base = SubscriptionProxy.inference_base
      end
      config.request_timeout = FirefightAi.configuration.request_timeout
      config.faraday_adapter = PUBLIC_ADDRESS_ADAPTER if checks_address_on_each_call?
    end
  end

  # An address the workspace named is resolved and checked again before every call where private networks are refused,
  # so a name that later resolves inside Firefight's network is never reached.
  def checks_address_on_each_call?
    settings.to_h[AiProviders::ADDRESS_SETTING].present? && !Entitlements.private_ai_endpoints?(workspace)
  end

  # The model and payer for a call with the purpose, on this account.
  # A code fix is written on the model the provider recommends for writing code and reviewed on the one it recommends
  # for reviewing it, each while the registry can price it, and on the main model otherwise.
  def choice_for(purpose)
    model = recommended_for(purpose) || model_for(AiPurpose.quick?(purpose) ? FAST : MAIN)
    if subscription?
      return FirefightAi::ModelChoice.new(model: SubscriptionProxy.model_for(workspace, model), provider: AiProviders::SUBSCRIPTION_PROXY,
                                          context: llm_context, payer: AiPayer.account(self))
    end

    FirefightAi::ModelChoice.new(model: model, provider: provider, context: llm_context, payer: AiPayer.account(self))
  end

  def recommended_for(purpose)
    definition = provider_definition
    return unless definition

    case purpose
    when AiPurpose::CODE_FIX then definition.code_fix_model_ready
    when AiPurpose::CODE_REVIEW then definition.code_review_model_ready || definition.code_fix_model_ready
    end
  end
  private :recommended_for

  # "Key ending in 4f2a. Enter a new one to replace it.", or nil before any key is stored.
  def credential_summary
    return credential_hint.present? ? "Signed in as #{credential_hint}." : "Signed in." if oauth? || subscription?
    return nil if credential_hint.blank?

    noun = provider_definition&.secret_fields&.first&.label || "Key"
    held = credential_hint.include?("@") ? "for #{credential_hint}" : "ending in #{credential_hint}"
    "#{noun} #{held}. Enter a new one to replace it."
  end

  # What the usable scope leaves out.
  def skipped? = !enabled || out_of_credit_since.present? || failing_since.present?

  STATE_DISABLED = :disabled
  STATE_OUT_OF_CREDIT = :out_of_credit
  STATE_FAILING = :failing
  STATE_VERIFIED = :verified
  STATE_UNCHECKED = :unchecked
  # A subscription whose sign-in no longer works, and one at its limit until it resets. What Halon does with either is
  # what it does with any account: a refused sign-in is skipped like a refused key, and a limit is a provider that
  # does not answer for now.
  STATE_SIGNED_OUT = :signed_out
  STATE_LIMIT_REACHED = :limit_reached
  STATES = [ STATE_VERIFIED, STATE_UNCHECKED, STATE_OUT_OF_CREDIT, STATE_FAILING, STATE_SIGNED_OUT, STATE_LIMIT_REACHED, STATE_DISABLED ].freeze

  def state
    return STATE_DISABLED unless enabled
    return STATE_OUT_OF_CREDIT if out_of_credit_since
    return STATE_SIGNED_OUT if signed_out?
    return STATE_LIMIT_REACHED if limit_reached?
    return STATE_FAILING if failing_since
    return STATE_VERIFIED if verified_at

    STATE_UNCHECKED
  end

  # One statement moves it, and only the call that moved it answers true, so of two calls refused at once only one
  # tells the admins (AiRefusal).
  def ran_out!(error)
    stuck!(:out_of_credit_since, error)
  end

  def key_refused!(error)
    stuck!(:failing_since, error)
  end

  # Every answered call says it works.
  def answered!
    self.class.where(id: id).update_all(last_used_at: Time.current, out_of_credit_since: nil, failing_since: nil, last_error: nil,
                                        updated_at: Time.current)
  end

  def checked!
    now = Time.current
    self.class.where(id: id).update_all(verified_at: now, out_of_credit_since: nil, failing_since: nil, last_error: nil, updated_at: now)
    reload
  end

  # A check the account failed keeps it out of use until a check passes, without telling the admins, since one of them
  # is looking at the result. A provider too busy to answer says nothing about the account, so it stays in use.
  def check_failed!(error)
    words = AiAccountError.words(error, model: model_for(FAST))
    changes = { verified_at: nil, last_error: words, updated_at: Time.current }
    unless error.is_a?(FirefightAi::TransientError)
      changes[AiPayer.out_of_credit?(error) ? :out_of_credit_since : :failing_since] = Time.current
    end
    self.class.where(id: id).update_all(changes)
    reload
  end

  def disable!
    update!(enabled: false)
  end

  def enable!
    update!(enabled: true)
  end

  # What deleting it means for Halon, in the confirmation.
  def deletion_consequence
    later = workspace.workspace_ai_accounts.enabled.where.not(id: id).exists?
    house = AiFunding.house_payer(workspace)
    return "Halon will use the next account." if later || house

    "Halon will have no AI account to use until an admin adds one."
  end

  private

  def secrets
    JSON.parse(credentials.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def write_secrets(values)
    self.credentials = values.compact_blank.to_json
    self.credential_hint = hint_for(values)
  end

  # The last few characters of the first secret, or the address a service account key is for, which is not a secret.
  def hint_for(values)
    return values["email"].presence || credential_hint if oauth?

    field = provider_definition&.secret_fields&.find { |candidate| values[candidate.key].present? }
    return nil unless field

    value = values[field.key].to_s
    email = (JSON.parse(value)["client_email"] if value.start_with?("{"))
    email.presence || value.last(HINT_LENGTH)
  rescue JSON::ParserError
    value.last(HINT_LENGTH)
  end

  def context_values
    values = settings.to_h.merge(secrets)
    return values unless oauth?

    sign_in = provider_definition&.sign_in
    values.merge("api_key" => secrets["access_token"], "api_base" => sign_in&.api_base)
  end

  def stuck!(column, error)
    moved = self.class.where(id: id, column => nil)
                .update_all(column => Time.current, :last_error => AiAccountError.words(error, model: nil), :updated_at => Time.current) == 1
    association(:workspace).target&.forget_held_read(:usable_ai_accounts)
    moved
  end

  def provider_offered
    return errors.add(:provider, "is not a subscription Firefight offers") if subscription? && subscription_definition.nil?
    return if subscription?
    return errors.add(:provider, "is not one Firefight offers") unless provider_definition
    return if AiProviders.offered_to?(workspace, provider)

    errors.add(:provider, "runs on a private network, which Firefight does not reach")
  end

  def settings_complete
    definition = provider_definition
    return unless definition
    return if oauth? || subscription?

    values = settings.to_h.merge(secrets)
    definition.fields.select(&:required).each do |field|
      errors.add(:base, "#{field.label} is required") if values[field.key].blank?
    end
    return if errors.any?

    errors.add(:base, "These settings are not enough to reach #{definition.name}") unless definition.configured?(llm_context.config)
  end

  # Halon makes room in a long run from how much the main model can read, so a model the registry cannot size never
  # runs an investigation. Quick work is one call and needs no size.
  def models_known
    return subscription_models_known if subscription?
    return unless provider_definition

    ROLES.each do |role|
      model = model_for(role)
      next errors.add(:"models.#{role}", "needs a model") if model.blank?
      next if role == FAST || FirefightAi.context_window(model, provider: provider)

      errors.add(:"models.#{role}", "is a model Firefight does not know the size of, so Halon cannot run on it. Choose another, or ask whoever runs Firefight to add it to the model registry")
    end
  end

  # A subscription runs only models its sign-in serves, and the main one must say how much it reads.
  def subscription_models_known
    ROLES.each do |role|
      model = model_for(role)
      next errors.add(:"models.#{role}", "needs a model") if model.blank?

      known = proxy_models.find { |entry| entry["id"] == model }
      next errors.add(:"models.#{role}", "is not a model this subscription serves") unless known
      next if role == FAST || known["context_window"].to_i.positive?

      errors.add(:"models.#{role}", "does not say how much it can read, so Halon cannot run on it. Choose another")
    end
  end

  def host_names_plain
    provider_definition&.fields&.each do |field|
      value = settings.to_h[field.key]
      next unless AiProviders::HOST_NAME_SETTINGS.include?(field.key)
      next if value.blank? || value.to_s.match?(AiProviders::HOST_NAME)

      errors.add(:base, "#{field.label} should be a name such as us-east-1")
    end
  end

  def address_allowed
    address = settings.to_h[AiProviders::ADDRESS_SETTING]
    return if address.blank?

    reason = AiAccountAddress.refusal(address, private_allowed: Entitlements.private_ai_endpoints?(workspace))
    errors.add(:base, reason) if reason
  end
end
