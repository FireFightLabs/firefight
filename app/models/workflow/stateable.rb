module Workflow::Stateable
  extend ActiveSupport::Concern

  included do
    enum :state, {
        pending: "pending",
        running: "running",
        paused: "paused",
        succeeded: "succeeded",
        failed: "failed",
        cancelled: "cancelled"
      }

    scope :completed, -> { where(state: %w[succeeded failed cancelled]) }
    scope :active, -> { where(state: %w[pending running]) }
    scope :stuck, ->(threshold = 5.minutes.ago) { active.where("updated_at < ?", threshold) }
  end


  def transition_to!(new_state)
    update!(state: new_state, "#{new_state}_at": Time.current)
    record_event("workflow.#{new_state}")
  end

  def completed?
    succeeded? || failed? || cancelled?
  end

  def active?
    pending? || running?
  end
end
