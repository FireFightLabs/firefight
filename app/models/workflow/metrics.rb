module Workflow::Metrics
  extend ActiveSupport::Concern

  class_methods do
    # Get summary statistics for workflows in a time range
    #
    # @param time_range [Range] Time range to analyze (default: last hour)
    # @return [Hash] Summary statistics including counts, averages, and failure rates
    #
    # @example
    #   Workflow.summary
    #   # => {
    #   #   total: 45,
    #   #   by_state: { "succeeded" => 40, "running" => 3, "failed" => 2 },
    #   #   by_workflow_class: { "IncidentCreation" => 30, "UserOnboarding" => 15 },
    #   #   avg_duration: 125.5,
    #   #   stuck_count: 1
    #   # }
    #
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

    # Calculate average workflow duration for succeeded workflows
    #
    # @param time_range [Range] Time range to analyze
    # @return [Float, nil] Average duration in seconds, or nil if no completed workflows
    #
    # @example
    #   Workflow.average_duration(24.hours.ago..)
    #   # => 125.5
    #
    def average_duration(time_range: 1.day.ago..)
      where(state: :succeeded)
        .where(created_at: time_range)
        .average("EXTRACT(EPOCH FROM (completed_at - created_at))")
        &.to_f
        &.round(2)
    end

    # Calculate failure rate as a percentage
    #
    # @param workflow_class [String, nil] Optional workflow class to filter by
    # @param time_range [Range] Time range to analyze
    # @return [Float] Failure rate as a percentage (0-100)
    #
    # @example
    #   Workflow.failure_rate
    #   # => 4.5
    #
    #   Workflow.failure_rate(workflow_class: "IncidentCreation", time_range: 7.days.ago..)
    #   # => 2.1
    #
    def failure_rate(workflow_class: nil, time_range: 24.hours.ago..)
      scope = where(created_at: time_range)
      scope = scope.where(workflow_class: workflow_class) if workflow_class

      total = scope.count
      return 0.0 if total.zero?

      failed = scope.where(state: :failed).count
      (failed.to_f / total * 100).round(2)
    end

    # Get workflows grouped by state with counts
    #
    # @param time_range [Range] Time range to analyze
    # @return [Hash] State counts
    #
    # @example
    #   Workflow.state_summary
    #   # => { "succeeded" => 45, "running" => 3, "failed" => 2 }
    #
    def state_summary(time_range: 1.hour.ago..)
      where(created_at: time_range).group(:state).count
    end

    # Find workflows that have exceeded their configured timeout
    #
    # @return [Array<Workflow>] Timed out workflows
    #
    # @example
    #   Workflow.timed_out
    #   # => [#<Workflow ...>]
    #
    def timed_out
      active.select(&:timed_out?)
    end
  end

  # Calculate duration for this workflow instance
  #
  # @return [Float, nil] Duration in seconds, or nil if not completed
  #
  # @example
  #   workflow.duration
  #   # => 125.5
  #
  def duration
    return nil unless completed_at
    completed_at - created_at
  end

  # Check if this workflow appears to be stuck
  #
  # A workflow is considered stuck if it's still active (pending/running)
  # but hasn't been updated in 30+ minutes
  #
  # @return [Boolean] true if stuck
  #
  # @example
  #   workflow.stuck?
  #   # => false
  #
  def stuck?
    active? && updated_at < 30.minutes.ago
  end

  # Check if this workflow has exceeded its configured timeout
  #
  # @return [Boolean] true if timed out
  #
  # @example
  #   workflow.timed_out?
  #   # => false
  #
  def timed_out?
    return false unless active?
    return false unless workflow_config.dig("timeout")

    timeout_seconds = workflow_config["timeout"].to_i
    running_duration = Time.current - (started_at || created_at)
    running_duration > timeout_seconds
  end
end
