# "Configured for prod" is this row, "permitted in prod" is a grant. The
# gateway requires both.
class IntegrationEnvironment < ApplicationRecord
  include IntegrationEnvironment::LiveUpdates

  HEALTH_UNKNOWN = "unknown"
  HEALTH_HEALTHY = "healthy"
  HEALTH_FAILING = "failing"
  HEALTH_STATUSES = [ HEALTH_UNKNOWN, HEALTH_HEALTHY, HEALTH_FAILING ].freeze
  OAUTH_KEY = "oauth".freeze
  # What the connect form asked for this environment (IntegrationProvider::ConnectField), and what the connection's health
  # check learned about it. Neither is a secret. Provider code reads both through Integrations::ConnectionSettings.
  FIELDS_KEY = "fields".freeze
  LEARNED_KEY = "learned".freeze
  # The app installation a connection was made through, such as a GitHub App's.
  INSTALLATION_KEY = "installation_id".freeze

  belongs_to :integration
  belongs_to :environment, class_name: "CatalogEntry", foreign_key: :catalog_entry_id,
             optional: true, inverse_of: false

  encrypts :credentials

  validates :health_status, inclusion: { in: HEALTH_STATUSES }
  validates :catalog_entry_id, uniqueness: { scope: :integration_id }

  # The resources it reports are found by the environment it is wired to.
  after_update_commit :index_reported_resources, if: :saved_change_to_catalog_entry_id?

  scope :enabled, -> { where(enabled: true) }
  # Rows that reach something: enabled, of a connection that is switched on and not removed, and not wired to an
  # environment that was deleted.
  scope :reachable, -> {
    enabled.joins(:integration).left_joins(:environment).where(integrations: { disabled_at: nil, deleted_at: nil })
           .merge(where(catalog_entry_id: nil).or(where(catalog_entries: { deleted_at: nil })))
  }

  def credentials_hash
    JSON.parse(credentials.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def request_headers
    creds = credentials_hash
    return creds["headers"] if creds["headers"].is_a?(Hash)
    return { "Authorization" => creds["authorization"] } if creds["authorization"].present?

    {}
  end

  # Produced and read by Integrations::OauthClient, nothing else looks inside.
  def oauth
    credentials_hash[OAUTH_KEY]
  end

  def store_oauth!(oauth_credentials)
    update!(credentials: credentials_hash.merge(OAUTH_KEY => oauth_credentials).to_json)
    oauth_credentials
  end

  # The install-first path, such as a GitHub App. Only an installation id
  # comes back, tokens are minted from it at call time.
  def store_installation!(installation_id)
    update!(base_config: base_config.merge(INSTALLATION_KEY => installation_id.to_s))
  end

  def installation_id = base_config.to_h[INSTALLATION_KEY].presence

  def fields = base_config.to_h.fetch(FIELDS_KEY, {})

  # Each connect sets them again, so a field left empty this time is gone.
  def store_fields!(values)
    update!(base_config: base_config.to_h.merge(FIELDS_KEY => values.to_h.stringify_keys))
  end

  # A field chosen after connecting from what the connection learned (IntegrationProvider::ConnectField with learned).
  # Answers why the value cannot be chosen, or nil once it is kept.
  def choose!(field, value)
    refusal = field.refusal(value, choices: field.options_from(learned))
    return refusal if refusal

    update!(base_config: base_config.to_h.merge(FIELDS_KEY => fields.merge(field.key => field.value_of(value)).compact_blank))
    nil
  end

  # Sets what the connection reads at its provider, the scopes its connect form chose (IntegrationProvider::ConnectField,
  # scope), one, several, or ConnectField::ALL. Each must be one the credential can read now. Answers why they cannot be
  # chosen, or nil once they are kept.
  def choose_scopes!(field, given)
    values = field.value_of(given)
    refusal = field.refusal(values)
    return refusal if refusal

    unless values == [ IntegrationProvider::ConnectField::ALL ]
      listed = Integrations::ConnectionSettings.of(self).scope_options.map(&:value)
      missing = values - listed
      return "This token cannot read #{field.reach_words(missing)}. Choose from what it lists." if missing.any?
    end

    update!(base_config: base_config.to_h.merge(FIELDS_KEY => fields.merge(field.key => values)))
    nil
  rescue Integrations::Error => error
    error.message
  end

  def learned = base_config.to_h.fetch(LEARNED_KEY, {})

  # The probe owns the shape of what it learned, this row owns writing it.
  def store_learned!(value)
    update!(base_config: base_config.to_h.merge(LEARNED_KEY => value))
  end

  # Adapters own the shape of what they cache, this row owns writing it.
  def store_credential!(key, value)
    update!(credentials: credentials_hash.merge(key => value).to_json)
  end

  def rotate_oauth!(oauth_credentials)
    update!(credentials: credentials_hash.merge(OAUTH_KEY => oauth_credentials).to_json)
    oauth_credentials
  end

  def record_health!(healthy, error: nil)
    update!(health_status: healthy ? HEALTH_HEALTHY : HEALTH_FAILING,
            health_error: healthy ? nil : error, health_checked_at: Time.current)
  end

  private

  def index_reported_resources
    reported = ResourceMap::Resource.where(integration_environment_id: id).or(ResourceMap::Resource.where("sightings ? :row", row: id.to_s))
    SearchDocument.index_later(ResourceMap::Resource, reported.pluck(:id))
  end
end
