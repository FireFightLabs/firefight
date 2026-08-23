module SolidWorkflow
  class Workflow < Record
    module Stateable
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
        scope :stuck, ->(threshold = SolidWorkflow.stuck_workflow_threshold.ago) { active.where("updated_at < ?", threshold) }
      end

      TERMINAL_STATES = %w[succeeded failed cancelled].freeze

      # Every state change goes through one guarded statement, so two writers
      # racing for the same workflow (the sweeper against the orchestrator, a
      # cancel against a completing step) cannot both win. Returns false when
      # the row was no longer in one of the `from` states, which callers treat
      # as "someone else got there first".
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
        reload if moved
        moved
      end

      def state_timestamps_merge_sql(state, timestamp)
        state_value = self.class.connection.quote(state.to_s)
        timestamp_value = self.class.connection.quote(timestamp.iso8601)
        Arel.sql("coalesce(state_timestamps, '{}'::jsonb) || jsonb_build_object(#{state_value}, #{timestamp_value})")
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
