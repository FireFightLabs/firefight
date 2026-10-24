# One change to a workflow, by a person or by Halon, with Halon's reason when it made it. An applied edit names the
# draft revision it was made on and the one it produced, which is what the history and undo are read from. A proposal
# is Halon's change waiting on top of what is there, grouped with the rest of its change set and the run or chat that
# prompted it, until a person accepts or dismisses it.
class Workflow::Edit < ApplicationRecord
  self.table_name = "workflow_edits"

  # A change that cannot be made, with the sentence that says why.
  class Refused < StandardError; end

  OPERATION_ADD_STEP = "add_step".freeze
  OPERATION_REMOVE_STEP = "remove_step".freeze
  OPERATION_MOVE_STEP = "move_step".freeze
  OPERATION_CONNECT = "connect".freeze
  OPERATION_DISCONNECT = "disconnect".freeze
  OPERATION_CHANGE_CONFIG = "change_config".freeze
  OPERATION_CHANGE_TRIGGER = "change_trigger".freeze
  OPERATION_RENAME = "rename".freeze
  OPERATIONS = [
    OPERATION_ADD_STEP, OPERATION_REMOVE_STEP, OPERATION_MOVE_STEP, OPERATION_CONNECT, OPERATION_DISCONNECT,
    OPERATION_CHANGE_CONFIG, OPERATION_CHANGE_TRIGGER, OPERATION_RENAME
  ].freeze

  STATUS_APPLIED = "applied".freeze
  STATUS_PROPOSED = "proposed".freeze
  STATUS_ACCEPTED = "accepted".freeze
  STATUS_DISMISSED = "dismissed".freeze
  STATUSES = [ STATUS_APPLIED, STATUS_PROPOSED, STATUS_ACCEPTED, STATUS_DISMISSED ].freeze
  # Edits that changed a draft.
  LANDED = [ STATUS_APPLIED, STATUS_ACCEPTED ].freeze

  TARGET_TRIGGER = "trigger".freeze
  TARGET_OUTPUTS = "outputs".freeze
  TARGET_WORKFLOW = "workflow".freeze

  include Workflow::Edit::Wording
  include Workflow::Edit::Changes
  include Workflow::LiveSignal

  shown_on_workflow_page PART_CANVAS

  belongs_to :workflow, inverse_of: :edits
  belongs_to :version, class_name: "Workflow::Version", optional: true, inverse_of: :edits
  belongs_to :author, class_name: "WorkspaceMembership", optional: true
  belongs_to :decided_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :source_run, class_name: "Workflow::Run", optional: true
  belongs_to :source_chat, class_name: "Chat", optional: true

  validates :operation, inclusion: { in: OPERATIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :author_kind, inclusion: { in: Workflow::AUTHOR_KINDS }
  validates :reason, presence: true, if: :by_halon?

  scope :landed, -> { where(status: LANDED) }

  def self.workflow_rename?(operation, payload) = operation == OPERATION_RENAME && payload.to_h.stringify_keys["step_id"].blank?

  def by_halon? = author_kind == Workflow::AUTHOR_HALON

  def proposed? = status == STATUS_PROPOSED

  # Applies a proposal to the draft, opened from the live version when there is none. Claimed first with one guarded
  # update, so two people accepting at once apply it once, and a refusal leaves it proposed.
  def accept!(by:)
    transaction do
      claimed = self.class.where(id: id, status: STATUS_PROPOSED)
                          .update_all(status: STATUS_ACCEPTED, decided_by_id: by&.id, decided_at: Time.current, updated_at: Time.current)
      raise Refused, "This suggestion was already decided." unless claimed == 1

      if self.class.workflow_rename?(operation, payload)
        workflow.update!(name: payload["name"])
      else
        draft = workflow.open_draft!(by: by)
        draft.apply_operation!(operation, payload, base_revision: draft.revision) do |applied_revision|
          self.class.where(id: id).update_all(version_id: draft.id, base_revision: draft.revision, applied_revision: applied_revision)
        end
      end
    end
    signal_workflow_page
    reload
  end

  def dismiss!(by:)
    moved = self.class.where(id: id, status: STATUS_PROPOSED)
                      .update_all(status: STATUS_DISMISSED, decided_by_id: by&.id, decided_at: Time.current, updated_at: Time.current)
    raise Refused, "This suggestion was already decided." unless moved == 1

    signal_workflow_page
    reload
  end
end
