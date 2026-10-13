# Something a workspace runs again and again: a trigger and a graph of steps that read, judge, wait, ask and change.
# What it does is kept as versions. One is live, at most one draft is open, and people and Halon change the draft one
# attributed edit at a time. A run records the version it started on and runs from a snapshot of it, so editing never
# changes a run already going.
#
# A run acts as the workflow's own identity (agent), whoever started it, never as the person who pressed Run. Who may
# publish is the gateway's to answer, never a check here. A new workflow has no cost cap until someone sets one.
class Workflow < ApplicationRecord
  include NormalizedDescription
  include Workflow::Naming
  include Workflow::Editing

  AUTHOR_PERSON = "person".freeze
  AUTHOR_HALON = "halon".freeze
  AUTHOR_KINDS = [ AUTHOR_PERSON, AUTHOR_HALON ].freeze
  NAME_LIMIT = 120

  belongs_to :workspace
  # The team on the catalog that owns it.
  belongs_to :owner_team, class_name: "CatalogEntry", optional: true
  # The machine principal its runs act as, nil until one is made for it.
  belongs_to :agent, optional: true
  belongs_to :live_version, class_name: "Workflow::Version", optional: true
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
  has_many :versions, class_name: "Workflow::Version", inverse_of: :workflow
  has_many :edits, class_name: "Workflow::Edit", inverse_of: :workflow
  has_many :runs, class_name: "Workflow::Run", inverse_of: :workflow

  validates :name, presence: true, length: { maximum: NAME_LIMIT }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }, format: { with: /\A[a-z0-9_]+\z/ }
  validates :cost_cap_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :owner_is_a_team

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }

  def draft = versions.find_by(status: Workflow::Version::STATUS_DRAFT)

  # Why a run cannot start now, as a sentence, or nil when it can.
  def start_blocked_reason
    return "Workflows are not switched on for this workspace." unless FeatureFlags.enabled?(workspace, FeatureFlags::WORKFLOWS)
    return "#{name} is switched off." unless enabled?
    return "#{name} has no published version to run." unless live_version

    nil
  end

  private

  def owner_is_a_team
    return if owner_team.nil?
    return errors.add(:owner_team, "must belong to this workspace") unless owner_team.workspace_id == workspace_id

    errors.add(:owner_team, "must be a team on the catalog") unless owner_team.catalog_type&.system_key == CatalogType::SYSTEM_KEY_TEAM
  end
end
