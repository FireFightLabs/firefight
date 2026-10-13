module SolidWorkflow
  class Workflow < Record
    module Stateable
      extend ActiveSupport::Concern

      included do
        enum :state, {
          pending: "pending",
          running: "running",
          waiting: "waiting",
          paused: "paused",
          succeeded: "succeeded",
          failed: "failed",
          cancelled: "cancelled"
        }

        scope :completed, -> { where(state: %w[succeeded failed cancelled]) }
        scope :active, -> { where(state: %w[pending running]) }
        # Not finished and not paused, including runs parked on a step that waits.
        scope :live, -> { where(state: %w[pending running waiting]) }
        scope :stuck, ->(threshold = SolidWorkflow.stuck_workflow_threshold.ago) { active.where("updated_at < ?", threshold) }
        # Parked runs a step was woken in while nothing could move them, such as a run its host held back.
        scope :stalled, lambda { |threshold = SolidWorkflow.stuck_workflow_threshold.ago|
          woken = SolidWorkflow::Step.where(status: "pending").where("wake_requests > 0")
                                     .where("solid_workflow_steps.workflow_id = solid_workflow_workflows.id")
          where(state: "waiting").where("updated_at < ?", threshold).where(woken.arel.exists)
        }
      end

      TERMINAL_STATES = %w[succeeded failed cancelled].freeze

      # One guarded statement, so two racing writers such as the sweeper against the orchestrator
      # cannot both win. Returns false when the row already left the `from` states.
      def transition!(new_state, from:, **columns)
        now = Time.current
        attributes = columns.merge(
          state: new_state,
          updated_at: now,
          state_timestamps: state_timestamps_merge_sql(new_state, now)
        )

        case new_state.to_s
        when "running"
          attributes[:started_at] = started_at || now
          attributes[:completed_at] = nil
        when *TERMINAL_STATES
          attributes[:completed_at] = now
        end

        moved = self.class.where(id: id, state: Array(from).map(&:to_s)).update_all(attributes) > 0
        return false unless moved

        reload
        parent_step&.wake!(reason: "child_finished") if TERMINAL_STATES.include?(new_state.to_s)
        true
      end

      def state_timestamps_merge_sql(state, timestamp)
        Arel.sql(self.class.sanitize_sql_array([ "coalesce(state_timestamps, '{}'::jsonb) || jsonb_build_object(?, ?)", state.to_s, timestamp.iso8601 ]))
      end

      def completed?
        succeeded? || failed? || cancelled?
      end

      def active?
        pending? || running?
      end
    end
  end
end
