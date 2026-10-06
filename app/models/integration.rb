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
  def self.server_url_for(workspace, entry, name, region_key, fields, kind: entry.kind)
    path_values = entry.connect_values(fields, entry.address_fields)
    existing = workspace.integrations.find_by(slug: slug_for(name), provider: entry.key, kind: kind)
    same = existing&.server_url.present? && existing.region == entry.region(region_key) && existing.address_fields == path_values
    same ? existing.server_url : entry.server_url_for(region_key, path_values)
  end

  # Why connecting another environment in this region, with these fields of the server's address, would move the
  # connection's other environments to a server their credentials are not for. nil when it would not.
  def move_blocked_reason(region, path_values, environment_id)
    return unless persisted?
    return if self.region == region && address_fields == path_values.to_h.stringify_keys
    return if integration_environments.none? { |row| row.catalog_entry_id != environment_id.presence }

    place = [ self.region&.label, *address_fields.values ].compact.join(", ").presence || server_url
    "#{name} reaches #{place} for its other environments. To connect somewhere else, add it as another account with its own name."
  end

  # The connect fields that are part of the server's address, in its path or its query (IntegrationProvider::ConnectField),
  # which belong to the whole connection.
  def address_fields = settings.to_h.fetch(FIELDS_SETTING, {})

  # How a person tells this connection from another one to the same provider, by the name it was given and the
  # provider's, such as "Faylee (Northflank)". A connection named after its provider is that name alone.
  def display_name
    provider_name = IntegrationProvider.find(provider)&.name
    return name if provider_name.blank? || provider_name.casecmp?(name.to_s.strip)

    "#{name} (#{provider_name})"
  end

  ACCOUNTS_SHOWN = 3

  # What the connection reaches, in words. That is its region and the connect fields that point it at an account, such as
  # "project faylee", or when it was asked none, the accounts its sweep put on the map. environment_row narrows it to one
  # environment. nil when nothing says.
  def reach(environment_row = nil)
    rows = environment_row ? [ environment_row ] : integration_environments.select(&:enabled)
    entry = IntegrationProvider.find(provider)
    fields = entry ? entry.address_fields + entry.environment_fields : []
    parts = fields.filter_map do |field|
      values = rows.flat_map { |row| Array(row.fields[field.key].presence || address_fields[field.key].presence) }.map(&:to_s).compact_blank.uniq
      "#{field.label.sub(/\A[A-Z](?![A-Z])/, &:downcase)} #{values.to_sentence}" if values.any?
    end
    parts = mapped_accounts(rows) if parts.empty?
    parts.unshift("region #{region.label}") if region && entry&.regions.to_a.size > 1
    parts.to_sentence.presence
  end

  # The connection and what it reaches, such as "Faylee (Northflank), project faylee", which is how a call through it is
  # put to a person.
  def target_label(environment_row = nil) = [ display_name, reach(environment_row) ].compact.join(", ")

  # Every word that names this connection or what it reaches, lowercased. These are its name and slug, its connect fields
  # and the accounts its sweep found. A word too short to tell connections apart is left out.
  def naming_terms
    rows = integration_environments.to_a
    values = rows.flat_map { |row| row.fields.values } + address_fields.values
    accounts = ResourceMap::Resource.where(workspace_id: workspace_id, integration_environment_id: rows.map(&:id)).distinct.pluck(:account)
    [ name, slug, slug.tr("_", " "), *values.flatten, *accounts, *accounts.flat_map { |account| account.split("/") } ]
      .map { |term| term.to_s.strip.downcase }.select { |term| term.length >= MIN_TERM }.uniq
  end

  MIN_TERM = 3

  # Saved row by row because enabling one mints its Ability::Action in an after_save that
  # update_all would skip. reads_only turns the write tools off rather than adding anything.
  def set_all_tools!(enabled, reads_only: false)
    transaction do
      tools.available.each do |tool|
        desired = enabled && (!reads_only || tool.read_only?) && (tool.enabled? || tool.namesake.nil?)
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

  # Why a new connection cannot take this name, or nil when it can. With a workspace, a name whose tools Halon would
  # call by another connection's tool's name is refused too.
  def self.name_blocked_reason(name, workspace: nil, provider: nil)
    return "All is kept for asking every connection at once. Pick a different name." if slug_for(name) == SLUG_ALL

    tool_name_collision_reason(workspace, name, provider) if workspace
  end

  # Halon calls a tool by its connection's slug and the tool's name joined with an underscore, so a connection named a_b
  # with a tool c and one named a with a tool b_c would both give it a_b_c. A connection has no tools until it is made,
  # so its tools are taken to be those its provider's other connections here have. A tool only discovered later that
  # still collides cannot be switched on (Integration::Tool#toggle_blocked_reason).
  def self.tool_name_collision_reason(workspace, name, provider)
    slug = slug_for(name)
    others = workspace.integrations.where(deleted_at: nil).where.not(slug: slug).includes(:tools).to_a
    own = others.select { |other| other.provider == provider.to_s }.flat_map { |other| other.tools.map(&:name) }.uniq
    others.each do |other|
      other.tools.each do |tool|
        mine = own.find { |each| "#{slug}.#{each}".tr(".", "_") == tool.model_facing_name }
        next unless mine

        return "#{name.to_s.strip} would give its #{mine} tool the name #{tool.model_facing_name}, which #{other.display_name}'s " \
               "#{tool.name} tool already has, so Halon could not tell them apart. Pick a different name."
      end
    end
    nil
  end

  # The connection each tool action key names, as a person tells it apart (display_name), read in one query. A removed
  # connection still names its old rows, and a system action names none.
  def self.display_names_for(workspace_id, action_keys) = connections_for(workspace_id, action_keys).transform_values(&:display_name)

  # The connection each tool action key runs through, read in one query.
  def self.connections_for(workspace_id, action_keys)
    keys = action_keys.map(&:to_s).uniq.select { |key| key.include?(".") }
    return {} if keys.empty?

    integrations = where(workspace_id: workspace_id, slug: keys.map { |key| key.split(".", 2).first }.uniq).includes(:tools)
                     .order(Arel.sql("deleted_at IS NOT NULL"), created_at: :desc).to_a
    keys.each_with_object({}) do |key, found|
      slug, tool_name = key.split(".", 2)
      integration = integrations.find { |each| each.slug == slug && each.tools.any? { |tool| tool.name == tool_name } }
      found[key] = integration if integration
    end
  end

  # This connection's tools that another connection's tool shares a name with as Halon calls it, by tool name, read in
  # one query.
  def tool_namesakes
    @tool_namesakes ||= begin
      names = tools.map(&:model_facing_name)
      others = Integration::Tool.joins(:integration).includes(:integration)
                                .where(integrations: { workspace_id: workspace_id, deleted_at: nil }).where.not(integration_id: id)
                                .where("replace(integrations.slug || '_' || integration_tools.name, '.', '_') IN (?)", names).to_a.index_by(&:model_facing_name)
      tools.each_with_object({}) { |tool, found| found[tool.name] = others[tool.model_facing_name] if others[tool.model_facing_name] }
    end
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

  def mapped_accounts(rows)
    accounts = ResourceMap::Resource.present.where(workspace_id: workspace_id, integration_environment_id: rows.map(&:id))
                                    .distinct.order(:account).limit(ACCOUNTS_SHOWN + 1).pluck(:account)
    return [] if accounts.empty?

    shown = accounts.first(ACCOUNTS_SHOWN)
    shown << "more" if accounts.size > ACCOUNTS_SHOWN
    [ "#{accounts.one? ? 'account' : 'accounts'} #{shown.to_sentence}" ]
  end

  def slug_not_reserved
    errors.add(:slug, "is kept for asking every connection at once") if slug == SLUG_ALL
  end
end
