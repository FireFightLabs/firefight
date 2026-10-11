# A test account an admin saved for one site, which Halon's browser signs in with when it checks a page there. It is kept
# on a connection row of the provider that keeps test logins (IntegrationProvider.test_logins), since only
# IntegrationEnvironment stores secrets: the password in its encrypted credentials, written through
# Integrations::SiteLogins, and the addresses and username as its fields, which are not secret. The password is never
# read back here. Reading it is SiteLogins', for one browser run.
class Integration::SiteLogin
  include ActiveModel::Model
  include ActiveModel::Attributes

  SITE_URL = "site_url".freeze
  LOGIN_URL = "login_url".freeze
  USERNAME = "username".freeze
  # When the password was last typed, which is all the page says of it, since even its last characters tell a short
  # password apart.
  PASSWORD_SET_AT = "password_set_at".freeze
  # A row's slug never changes and must not collide with a connection's, so it is made, never derived from the name.
  SLUG_PREFIX = "test_login_".freeze
  NAME_LIMIT = 100
  SCHEMES = %w[http https].freeze
  # Second-level labels that are a public suffix under a country code, such as co.uk, so example.co.uk is one site.
  SHORT_SECOND_LEVEL = 3

  attribute :name, :string
  attribute :site_url, :string
  attribute :login_url, :string
  attribute :username, :string
  attribute :password, :string

  attr_reader :workspace, :integration

  validate :site_is_an_address, :login_is_on_the_site, :username_given, :password_given, :name_fits

  def initialize(workspace:, integration: nil, **attributes)
    @workspace = workspace
    @integration = integration
    super(**attributes)
  end

  # Every saved login of the workspace, in name order.
  def self.all_in(workspace) = rows(workspace).order(:name).map { |integration| from(integration) }

  def self.find_in!(workspace, id) = from(rows(workspace).find(id))

  def self.rows(workspace)
    workspace.integrations.where(provider: IntegrationProvider.test_login_keys, deleted_at: nil).includes(:integration_environments)
  end

  def self.from(integration)
    fields = integration.integration_environments.first&.fields.to_h
    new(workspace: integration.workspace, integration: integration, name: integration.name, site_url: fields[SITE_URL],
        login_url: fields[LOGIN_URL], username: fields[USERNAME])
  end

  # The host a site is known by, lowercased and without a leading www, so www.shop.example.com and shop.example.com are
  # one site.
  def self.host_of(url)
    host = URI.parse(url.to_s.strip).host.to_s.downcase
    host.delete_prefix("www.").presence
  rescue URI::InvalidURIError
    nil
  end

  def id = integration&.id

  def persisted? = integration.present?

  def host = self.class.host_of(site_url)

  def environment_row = integration&.integration_environments&.first

  def password_set_at
    at = environment_row&.fields.to_h[PASSWORD_SET_AT]
    at && Time.zone.parse(at.to_s)
  end

  def password_hint
    at = password_set_at
    at ? "Password saved on #{at.strftime('%-d %b %Y')}" : "Password saved"
  end

  # Saves the login, keeping the password already saved when none was typed. One login per site, checked under the
  # workspace's lock so two admins saving the same site at once cannot both win.
  def save!
    raise ActiveModel::ValidationError, self unless valid?

    workspace.with_lock do
      raise ActiveModel::ValidationError, self unless unique_site?

      @integration ||= workspace.integrations.new(kind: Integration::KIND_NATIVE, provider: IntegrationProvider.test_logins.key,
                                                  slug: "#{SLUG_PREFIX}#{SecureRandom.hex(6)}")
      integration.update!(name: shown_name)
      row = integration.integration_environments.find_or_create_by!(catalog_entry_id: nil)
      set_at = password.present? ? Time.current.utc.iso8601 : row.fields[PASSWORD_SET_AT]
      row.store_fields!({ SITE_URL => site_url.strip, LOGIN_URL => login_url.to_s.strip.presence, USERNAME => username.strip,
                          PASSWORD_SET_AT => set_at }.compact)
      Integrations::SiteLogins.keep_password!(row, password) if password.present?
    end
    self
  end

  def destroy! = integration.destroy!

  private

  def shown_name = name.to_s.strip.presence || host

  def site_is_an_address
    refusal = address_refusal(site_url, "Site address")
    errors.add(:site_url, refusal) if refusal
  end

  def login_is_on_the_site
    return if login_url.blank?

    refusal = address_refusal(login_url, "Login page")
    return errors.add(:login_url, refusal) if refusal
    return if host.nil? || same_site?(self.class.host_of(login_url), host)

    errors.add(:login_url, "Login page must be on the same site as #{host}.")
  end

  def username_given
    errors.add(:username, "Enter the test account's username.") if username.to_s.strip.empty?
  end

  # A new login needs one. Editing keeps the saved password when the field is left empty.
  def password_given
    return if persisted? || password.present?

    errors.add(:password, Integrations::SiteLogins.password_refusal(password))
  end

  def name_fits
    errors.add(:name, "Name can be at most #{NAME_LIMIT} characters.") if name.to_s.strip.length > NAME_LIMIT
  end

  def address_refusal(url, label)
    uri = URI.parse(url.to_s.strip)
    return "#{label} must be an http or https address, such as https://shop.example.com." unless SCHEMES.include?(uri.scheme) && uri.host.present?

    "#{label} cannot hold a username or password. Put them in their own fields." if uri.userinfo.present?
  rescue URI::InvalidURIError
    "#{label} must be an http or https address, such as https://shop.example.com."
  end

  def unique_site?
    taken = self.class.all_in(workspace).find { |other| other.id != id && other.host == host }
    return true unless taken

    errors.add(:site_url, "A test login for #{host} is already saved. Edit that one instead.")
    false
  end

  # The same registrable domain, so a site whose login is on accounts.example.com still matches shop.example.com.
  def same_site?(one, other) = one.present? && registrable(one) == registrable(other)

  def registrable(host)
    labels = host.split(".")
    country_suffix = labels.size >= 3 && labels[-1].length == 2 && labels[-2].length <= SHORT_SECOND_LEVEL
    labels.last(country_suffix ? 3 : 2).join(".")
  end
end
