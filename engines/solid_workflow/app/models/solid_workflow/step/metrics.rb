module SolidWorkflow
  class Step < Record
    module Metrics
      extend ActiveSupport::Concern

      class_methods do
        def step_stats(workflow_class: nil, time_range: 1.hour.ago..)
          scope = joins(:workflow).where(solid_workflow_workflows: { created_at: time_range })
          scope = scope.where(solid_workflow_workflows: { workflow_class: workflow_class }) if workflow_class

          scope.group(:name, :status).count
        end

        def step_failure_rates(time_range: 24.hours.ago..)
          scope = where(created_at: time_range)

          totals = scope.group(:name).count
          failures = scope.where(status: :failed).group(:name).count

          totals.transform_values do |total|
            step_name = totals.key(total)
            failed_count = failures[step_name] || 0
            total.zero? ? 0.0 : (failed_count.to_f / total * 100).round(2)
          end
        end

        def average_step_durations(time_range: 24.hours.ago..)
          where(status: :succeeded)
            .where(created_at: time_range)
            .where.not(started_at: nil, completed_at: nil)
            .group(:name)
            .average("EXTRACT(EPOCH FROM (completed_at - started_at))")
            .transform_values { |v| v&.to_f&.round(2) }
        end
      end

      def duration
        return nil unless started_at && completed_at
        completed_at - started_at
      end
    end
  end
end
