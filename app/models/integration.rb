# A connected provider instance: credentials per environment, tools that
# mint gateway actions. kind selects the executor. mcp consumes any external
# MCP server, native runs a first-party Integrations::NativePack. http packs
# follow.
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
  validates :slug, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
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

  # The per-kind facade for talking to the provider (call, tool_definitions,
  # check_health!). The one place the kinds diverge. Everything downstream
  # stays executor-agnostic.
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

  # The environment is derived, never asserted. An explicit entry id must
  # match a wired row. No entry resolves to the global row, or to the single
  # wired environment when that is unambiguous.
  # Bulk allowlisting. Each row is saved on its own because enabling one
  # mints its Ability::Action in an after_save, and update_all would skip
  # that, leaving capabilities that look enabled but can never be granted.
  #
  # reads_only turns the read tools on *and the write ones off*, so it is a
  # statement of what the connection may do rather than an additive step
  # that quietly leaves earlier write grants in place.
  def set_all_tools!(enabled, reads_only: false)
    transaction do
      tools.each do |tool|
        desired = enabled && (!reads_only || tool.read_only?)
        tool.update!(enabled: desired) if tool.enabled? != desired
      end
    end
  end

  def resolve_environment(catalog_entry_id)
    rows = integration_environments.where(enabled: true)
    return rows.find_by(catalog_entry_id: catalog_entry_id) if catalog_entry_id.present?

    rows.find_by(catalog_entry_id: nil) || (rows.limit(2).to_a.then { |r| r.size == 1 ? r.first : nil })
  end

  private

  # Action keys derive from the slug. Renaming would orphan grants,
  # policies, and ledger rows referencing the old keys.
  def slug_immutable
    errors.add(:slug, "cannot be changed after creation") if slug_changed?
  end
end
