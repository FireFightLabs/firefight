class IncidentAction < ApplicationRecord
  include IncidentAction::Snapshots
  include IncidentAction::IssueLink

  ACTION_TYPE_ACTION = "action"
  ACTION_TYPE_FOLLOWUP = "followup"
  ACTION_TYPES = [ ACTION_TYPE_ACTION, ACTION_TYPE_FOLLOWUP ].freeze
  ACTION_TYPE_BY_KIND = { action: ACTION_TYPE_ACTION, followup: ACTION_TYPE_FOLLOWUP }.freeze

  STATUS_OPEN = "open"
  STATUS_IN_PROGRESS = "in_progress"
  STATUS_DONE = "done"
  STATUSES = [ STATUS_OPEN, STATUS_IN_PROGRESS, STATUS_DONE ].freeze

  belongs_to :incident
  # Polymorphic because an agent takes part as itself.
  belongs_to :created_by, polymorphic: true
  belongs_to :assignee, polymorphic: true, optional: true
  belongs_to :runbook_step, optional: true
  has_many :incident_action_updates, dependent: :destroy

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  # in_progress and having an assignee always agree.
  validate :status_matches_assignee
  validates :description, presence: true
  # A link to the issue tracking the work elsewhere, which every surface renders as a link.
  validates :external_url, format: { with: %r{\Ahttps?://[^\s<>|]+\z} }, length: { maximum: 2048 }, allow_nil: true

  scope :active, -> { where(deleted_at: nil) }
  # Interaction payloads carry ids from whoever clicked, so an unscoped lookup
  # could write to another tenant.
  scope :in_workspace, ->(workspace) { joins(:incident).where(incidents: { workspace_id: workspace.id }) }
  scope :actions, -> { where(action_type: ACTION_TYPE_ACTION) }
  scope :followups, -> { where(action_type: ACTION_TYPE_FOLLOWUP) }
  scope :open, -> { where(status: STATUS_OPEN) }
  scope :completed, -> { where(status: STATUS_DONE) }
  scope :recent, -> { order(created_at: :desc) }
  scope :tracking, ->(url) { active.where(external_url: url) }

  def claimable?
    pick_up_blocked_reason.nil?
  end

  def pick_up_blocked_reason
    return "That item is done. Reopen it first." if done?
    return "#{assignee&.actor_display_name || "Someone"} already holds that item." if assigned?

    "That item is already under way." unless open?
  end

  def completable?
    completion_blocked_reason.nil?
  end

  def completion_blocked_reason
    return nil unless done?

    "That item is already done."
  end

  # A title is what the item says needs doing, so it cannot be emptied.
  def rename_blocked_reason(description)
    return "Give the item a title." if description.to_s.strip.empty?

    "That is already its title." if description.to_s.strip == self.description
  end

  def reopen_blocked_reason
    return "That item is not done." unless done?

    incident.action_reopen_blocked_reason(action_type)
  end

  def unassign_blocked_reason
    return "That item is done. Reopen it first." if done?

    "Nobody holds that item." unless assigned?
  end

  # Open means nobody holds it, so a done item reopens and a held one is let go. An open one is already there.
  def open_blocked_reason
    reopen_blocked_reason if done?
  end

  # Every refusal a combined change could meet, checked before any of it is written so a refused request changes
  # nothing. A nil description means the title is not being changed.
  def change_blocked_reason(description: nil, status: nil)
    (rename_blocked_reason(description) unless description.nil?) ||
      (open_blocked_reason if status == STATUS_OPEN) ||
      (completion_blocked_reason if status == STATUS_DONE)
  end

  # Moves the item's status on only from where it was, so two people or a person and its issue never both land. False
  # when it had moved.
  def move_status!(from:, to:, **columns)
    won = self.class.where(id: id, status: Array(from)).update_all(status: to, updated_at: Time.current, **columns)
    reload
    won == 1
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

  # A url is already absolute, a message_ts needs the adapter to resolve one.
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

  def self.with_actors(actions)
    Principal.preload_users(actions.flat_map { |action| [ action.created_by, action.assignee ] })
    actions
  end

  def to_context_hash
    { type: action_type, description:, status:, assignee: assignee&.actor_display_name, external_key:, external_url: }.compact
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
