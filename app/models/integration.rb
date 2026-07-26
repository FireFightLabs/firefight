# A connected provider instance: credentials per environment, tools that
# mint gateway actions. kind selects the executor; v1 implements mcp
# (consume any external MCP server); http packs and native tools follow.
class Integration < ApplicationRecord
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

  before_validation :derive_slug, on: :create

  scope :active, -> { where(disabled_at: nil, deleted_at: nil) }

  def operational?
    disabled_at.nil? && deleted_at.nil?
  end

  def deleted?
    deleted_at.present?
  end

  def server_url
    settings["server_url"]
  end

  # The environment is derived, never asserted: an explicit entry id must
  # match a wired row; no entry resolves to the global row, or to the single
  # wired environment when that is unambiguous.
  def resolve_environment(catalog_entry_id)
    rows = integration_environments.where(enabled: true)
    return rows.find_by(catalog_entry_id: catalog_entry_id) if catalog_entry_id.present?

    rows.find_by(catalog_entry_id: nil) || (rows.limit(2).to_a.then { |r| r.size == 1 ? r.first : nil })
  end

  private

  def derive_slug
    self.slug = name.to_s.parameterize(separator: "_") if slug.blank?
  end

  # Action keys derive from the slug; renaming would orphan grants,
  # policies, and ledger rows referencing the old keys.
  def slug_immutable
    errors.add(:slug, "cannot be changed after creation") if slug_changed?
  end
end
