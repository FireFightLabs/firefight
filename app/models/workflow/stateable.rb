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
    current_time = Time.current
    attributes = {
      state: new_state,
      state_timestamps: (state_timestamps || {}).merge(new_state.to_s => current_time.iso8601)
    }

    case new_state.to_s
    when "running"
      attributes[:started_at] = current_time
    when "succeeded", "failed", "cancelled"
      attributes[:completed_at] = current_time
    end

    update!(attributes)
    record_event("workflow.#{new_state}")
  end

  def completed?
    succeeded? || failed? || cancelled?
  end

  def active?
    pending? || running?
  end
end
