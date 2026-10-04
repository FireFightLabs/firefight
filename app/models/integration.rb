# kind selects the executor. mcp consumes any external MCP server, native
# runs a first-party Integrations::NativePack.
class Integration < ApplicationRecord
  include Sluggable

  KIND_MCP = "mcp"
  KIND_HTTP = "http"
  KIND_NATIVE = "native"
  KINDS = [ KIND_MCP, KIND_HTTP, KIND_NATIVE ].freeze

  PROVIDER_CUSTOM_MCP = "custom_mcp"

  belongs_to :workspace
  has_many :integration_environments, dependent: :destroy
  has_many :tools, class_name: "Integration::Tool", dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :provider, :name, presence: true
  # all asks every connection at once (connection: all), so no connection can be called it.
  SLUG_ALL = "all".freeze

  validates :slug, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validate :slug_not_reserved, on: :create
  validates :slug, uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } },
                   unless: :deleted?
  validate :slug_immutable, on: :update

  scope :active, -> { where(disabled_at: nil, deleted_at: nil) }

  def operational?
    disabled_at.nil? && deleted_at.nil?
  end

  def native?
    kind == KIND_NATIVE
  end

  # The one place the kinds diverge.
  def executor
    case kind
    when KIND_MCP then Integrations::McpExecutor
    when KIND_NATIVE then Integrations::NativeExecutor
    else
      raise Integrations::Error, "No executor implemented for kind '#{kind}'"
    end
  end

  def deleted?
    deleted_at.present?
  end

  def server_url
    settings["server_url"]
  end

  # Where a connection keeps the region it was made in and the connect fields that are part of its server's address.
  REGION_SETTING = "region".freeze
  FIELDS_SETTING = "fields".freeze

  # The provider's region the connection was made in, by its key (IntegrationProvider::Region), or nil when none was
  # chosen.
  def region_key = settings.to_h[REGION_SETTING]

  # The region the connection was made in. One made by pasting a server's address is in the region that server is in,
  # and a native pack's connection made before its provider listed regions is in the first one. nil when the provider
  # lists none, or the pasted address is in none of them.
  def region
    entry = IntegrationProvider.find(provider)
    return unless entry
    return entry.region(region_key) if region_key.present?
    return entry.region_for_url(server_url) if server_url.present?

    entry.region if native?
  end

  # The server a connection named name is made to, in a region and with the fields entry's connect form asked. A
  # connection already there keeps the server it calls, so a token is never asked for one it does not, and a connection
  # made before its provider listed regions keeps its address. Otherwise it is the region's server with the fields that
  # are part of its address.
  def self.server_url_for(workspace, entry, name, region_key, fields)
    path_values = entry.connect_values(fields, entry.path_fields)
    existing = workspace.integrations.find_by(slug: slug_for(name), provider: entry.key, kind: entry.kind)
    same = existing&.server_url.present? && existing.region == entry.region(region_key) && existing.path_fields == path_values
    same ? existing.server_url : entry.server_url_for(region_key, path_values)
  end

  # Why connecting another environment in this region, with these fields of the server's address, would move the
  # connection's other environments to a server their credentials are not for. nil when it would not.
  def move_blocked_reason(region, path_values, environment_id)
    return unless persisted?
    return if self.region == region && path_fields == path_values.to_h.stringify_keys
    return if integration_environments.none? { |row| row.catalog_entry_id != environment_id.presence }

    place = [ self.region&.label, *path_fields.values ].compact.join(", ").presence || server_url
    "#{name} reaches #{place} for its other environments. To connect somewhere else, add it as another account with its own name."
  end

  # The connect fields that are part of the server's address (IntegrationProvider::ConnectField), which belong to the
  # whole connection.
  def path_fields = settings.to_h.fetch(FIELDS_SETTING, {})

  # Saved row by row because enabling one mints its Ability::Action in an after_save that
  # update_all would skip. reads_only turns the write tools off rather than adding anything.
  def set_all_tools!(enabled, reads_only: false)
    transaction do
      tools.available.each do |tool|
        desired = enabled && (!reads_only || tool.read_only?)
        tool.update!(enabled: desired) if tool.enabled? != desired
      end
    end
  end

  # The Integrations page reads these from its address, so a link opens one connection's details or one provider's connect dialog.
  DETAILS_QUERY_PARAM = "integration".freeze
  CONNECT_QUERY_PARAM = "connect".freeze

  def resolve_environment(catalog_entry_id)
    rows = integration_environments.where(enabled: true)
    return rows.find_by(catalog_entry_id: catalog_entry_id) if catalog_entry_id.present?

    rows.find_by(catalog_entry_id: nil) || (rows.limit(2).to_a.then { |r| r.size == 1 ? r.first : nil })
  end

  class UnknownEnvironment < StandardError; end

  # Why a new connection cannot take this name, or nil when it can.
  def self.name_blocked_reason(name)
    "All is kept for asking every connection at once. Pick a different name." if slug_for(name) == SLUG_ALL
  end

  # The environment a caller named by slug, or nil for the connection's default. Every way in
  # resolves it here, so an unknown one is refused with the same words from a chat and over MCP.
  def environment_entry_for(slug)
    return nil if slug.blank?

    workspace.catalog_entries.active.find_by(slug: slug.to_s) ||
      raise(UnknownEnvironment, "Unknown environment '#{slug}'.")
  end

  # The slugs a caller has to choose between, empty when the connection resolves one on its own.
  # Slugs are catalog data any member can read, so nothing is disclosed.
  def environment_choices
    return [] if resolve_environment(nil).present?

    slugs = integration_environments.enabled.includes(:environment).filter_map { |row| row.environment&.slug }
    slugs.size < 2 ? [] : slugs
  end

  private

  # Action keys derive from the slug, renaming would orphan grants, policies
  # and ledger rows.
  def slug_immutable
    errors.add(:slug, "cannot be changed after creation") if slug_changed?
  end

  def slug_not_reserved
    errors.add(:slug, "is kept for asking every connection at once") if slug == SLUG_ALL
  end
end
