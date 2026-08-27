class IncidentAction < ApplicationRecord
  include IncidentAction::Snapshots

  ACTION_TYPE_ACTION = "action"
  ACTION_TYPE_FOLLOWUP = "followup"
  ACTION_TYPES = [ ACTION_TYPE_ACTION, ACTION_TYPE_FOLLOWUP ].freeze
  ACTION_TYPE_BY_KIND = { action: ACTION_TYPE_ACTION, followup: ACTION_TYPE_FOLLOWUP }.freeze

  STATUS_OPEN = "open"
  STATUS_IN_PROGRESS = "in_progress"
  STATUS_DONE = "done"
  STATUSES = [ STATUS_OPEN, STATUS_IN_PROGRESS, STATUS_DONE ].freeze

  belongs_to :incident
  # Polymorphic because an agent takes part as itself, never on a person's
  # behalf. Both hold a WorkspaceMembership, an Agent or an ApiKey.
  belongs_to :created_by, polymorphic: true
  belongs_to :assignee, polymorphic: true, optional: true
  belongs_to :runbook_step, optional: true
  has_many :incident_action_updates, dependent: :destroy

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  # The service derives in_progress from having an assignee. The pair is a
  # model invariant so no future writer can store the contradiction.
  validate :status_matches_assignee
  validates :description, presence: true

  scope :active, -> { where(deleted_at: nil) }
  # Interaction payloads carry ids from whoever clicked, so a lookup that
  # crosses workspaces is a lookup that writes to another tenant.
  scope :in_workspace, ->(workspace) { joins(:incident).where(incidents: { workspace_id: workspace.id }) }
  scope :actions, -> { where(action_type: ACTION_TYPE_ACTION) }
  scope :followups, -> { where(action_type: ACTION_TYPE_FOLLOWUP) }
  scope :open, -> { where(status: STATUS_OPEN) }
  scope :completed, -> { where(status: STATUS_DONE) }
  scope :recent, -> { order(created_at: :desc) }

  # Nobody has taken it, so taking it is the next move. Both entry points ask
  # rather than each spelling out what an untaken item looks like.
  def claimable?
    open? && !assigned?
  end

  def completable?
    completion_blocked_reason.nil?
  end

  # A sentence or nil, so an entry point reports the rule rather than
  # restating it.
  def completion_blocked_reason
    return nil unless done?

    "That item is already done."
  end

  def open?
    status == STATUS_OPEN
  end

  def done?
    status == STATUS_DONE
  end

  def assigned?
    assignee_id.present?
  end

  def from_runbook_step?
    runbook_step_id.present?
  end

  # Where a reader should look to see this item in the context it came from.
  # A url is already absolute. A message_ts needs the adapter to resolve one.
  OriginReference = Data.define(:label, :url, :message_ts)

  def origin_reference
    source_link = platform_data["source_message_link"]
    return OriginReference.new(label: "From a message", url: source_link, message_ts: nil) if source_link.present?

    if from_runbook_step?
      attachment = incident.incident_runbooks.find_by(runbook_id: runbook_step.runbook_id)
      return OriginReference.new(label: runbook_step.runbook.name, url: nil, message_ts: attachment&.message_ts)
    end

    OriginReference.new(label: "View #{action_type == ACTION_TYPE_FOLLOWUP ? 'follow-up' : 'action'}", url: nil, message_ts: message_ts)
  end

  # Both actors are polymorphic, so the people among them get their users
  # preloaded and the machines are left alone.
  def self.with_actors(actions)
    Principal.preload_users(actions.flat_map { |action| [ action.created_by, action.assignee ] })
    actions
  end

  def to_context_hash
    { type: action_type, description:, status:, assignee: assignee&.actor_display_name }
  end

  private

  def status_matches_assignee
    if status == STATUS_IN_PROGRESS && assignee_id.blank?
      errors.add(:status, "cannot be in progress without an assignee")
    elsif status == STATUS_OPEN && assignee_id.present?
      errors.add(:status, "cannot stay open once someone is assigned")
    end
  end
end
