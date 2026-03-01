module SolidWorkflow
  class Workflow < Record
    module Metrics
      extend ActiveSupport::Concern

      class_methods do
        def summary(time_range: 1.hour.ago..)
          workflows = where(created_at: time_range)

          {
            total: workflows.count,
            by_state: workflows.group(:state).count,
            by_workflow_class: workflows.group(:workflow_class).count,
            avg_duration: average_duration(time_range),
            stuck_count: stuck.count
          }
        end

        def average_duration(time_range: 1.day.ago..)
          where(state: :succeeded)
            .where(created_at: time_range)
            .average("EXTRACT(EPOCH FROM (completed_at - created_at))")
            &.to_f
            &.round(2)
        end

        def failure_rate(workflow_class: nil, time_range: 24.hours.ago..)
          scope = where(created_at: time_range)
          scope = scope.where(workflow_class: workflow_class) if workflow_class

          total = scope.count
          return 0.0 if total.zero?

          failed = scope.where(state: :failed).count
          (failed.to_f / total * 100).round(2)
        end

        def state_summary(time_range: 1.hour.ago..)
          where(created_at: time_range).group(:state).count
        end

        def timed_out
          active.select(&:timed_out?)
        end
      end

      def duration
        return nil unless completed_at
        completed_at - created_at
      end

      def stuck?
        active? && updated_at < 30.minutes.ago
      end

      def timed_out?
        return false unless active?
        return false unless workflow_config.dig("timeout")

        timeout_seconds = workflow_config["timeout"].to_i
        running_duration = Time.current - (started_at || created_at)
        running_duration > timeout_seconds
      end
    end
  end
end
