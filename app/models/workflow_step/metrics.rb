module WorkflowStep::Metrics
  extend ActiveSupport::Concern

  class_methods do
    # Get step statistics grouped by name and status
    #
    # @param workflow_class [String, nil] Optional workflow class to filter by
    # @param time_range [Range] Time range to analyze
    # @return [Hash] Hash with [step_name, status] => count
    #
    # @example
    #   WorkflowStep.step_stats
    #   # => {
    #   #   ["create_channel", "succeeded"] => 45,
    #   #   ["create_channel", "failed"] => 2,
    #   #   ["post_message", "succeeded"] => 43
    #   # }
    #
    #   WorkflowStep.step_stats(workflow_class: "IncidentCreation")
    #   # => { ["create_channel", "succeeded"] => 30, ... }
    #
    def step_stats(workflow_class: nil, time_range: 1.hour.ago..)
      scope = joins(:workflow).where(workflows: { created_at: time_range })
      scope = scope.where(workflows: { workflow_class: workflow_class }) if workflow_class

      scope.group(:name, :status).count
    end

    # Get failure rate for specific steps
    #
    # @param time_range [Range] Time range to analyze
    # @return [Hash] Hash with step_name => failure_percentage
    #
    # @example
    #   WorkflowStep.step_failure_rates
    #   # => {
    #   #   "create_channel" => 4.5,
    #   #   "post_message" => 2.1,
    #   #   "invite_users" => 0.0
    #   # }
    #
    def step_failure_rates(time_range: 24.hours.ago..)
      scope = where(created_at: time_range)

      # Get total attempts per step
      totals = scope.group(:name).count

      # Get failures per step
      failures = scope.where(status: :failed).group(:name).count

      # Calculate percentages
      totals.transform_values do |total|
        step_name = totals.key(total)
        failed_count = failures[step_name] || 0
        total.zero? ? 0.0 : (failed_count.to_f / total * 100).round(2)
      end
    end

    # Get average execution time per step
    #
    # @param time_range [Range] Time range to analyze
    # @return [Hash] Hash with step_name => avg_duration_seconds
    #
    # @example
    #   WorkflowStep.average_step_durations
    #   # => {
    #   #   "create_channel" => 2.5,
    #   #   "post_message" => 1.2,
    #   #   "invite_users" => 3.8
    #   # }
    #
    def average_step_durations(time_range: 24.hours.ago..)
      where(status: :succeeded)
        .where(created_at: time_range)
        .where.not(started_at: nil, completed_at: nil)
        .group(:name)
        .average("EXTRACT(EPOCH FROM (completed_at - started_at))")
        .transform_values { |v| v&.to_f&.round(2) }
    end
  end

  # Calculate execution duration for this step instance
  #
  # @return [Float, nil] Duration in seconds, or nil if not completed
  #
  # @example
  #   step.duration
  #   # => 2.5
  #
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
