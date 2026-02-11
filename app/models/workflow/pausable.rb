module Workflow::Pausable
  extend ActiveSupport::Concern

  # Pause a running workflow
  #
  # Stops workflow orchestration until resume! is called.
  # Useful for:
  # - Waiting for human approval
  # - Scheduled maintenance windows
  # - Rate limiting / backpressure
  # - Manual intervention
  #
  # @param reason [String] Why the workflow was paused
  # @param by [String] Who/what paused it (email, user_id, or "system")
  #
  # @example Wait for manager approval
  #   workflow.pause!(
  #     reason: "Waiting for manager approval on $50k purchase",
  #     by: "approval_system"
  #   )
  #
  # @example Rate limiting
  #   workflow.pause!(
  #     reason: "Slack API rate limit hit",
  #     by: "system"
  #   )
  #
  def pause!(reason: nil, by: nil)
    return if completed?

    transaction do
      current_time = Time.current
      update!(
        state: :paused,
        workflow_config: workflow_config.merge(
          paused_at: current_time.iso8601,
          paused_by: by,
          pause_reason: reason
        ),
        state_timestamps: (state_timestamps || {}).merge("paused" => current_time.iso8601)
      )

      record_event(WorkflowEvents::Workflow::PAUSED, reason: reason, by: by)
    end

    Rails.logger.info({
      event: "workflow.paused",
      workflow_id: id,
      workflow_class: workflow_class,
      reason: reason,
      by: by
    })
  end

  # Resume a paused workflow
  #
  # Resumes orchestration and schedules ready steps.
  #
  # @param by [String] Who/what resumed it (email, user_id, or "system")
  #
  # @example Manager approves
  #   workflow.resume!(by: "manager@example.com")
  #
  # @example Automated resume after delay
  #   ResumeWorkflowJob.set(wait: 60.seconds).perform_later(workflow.id)
  #
  def resume!(by: nil)
    return unless paused?

    transaction do
      current_time = Time.current
      update!(
        state: :running,
        workflow_config: workflow_config.merge(
          resumed_at: current_time.iso8601,
          resumed_by: by
        ),
        state_timestamps: (state_timestamps || {}).merge("running" => current_time.iso8601)
      )

      record_event(WorkflowEvents::Workflow::RESUMED, by: by)
    end

    Rails.logger.info({
      event: "workflow.resumed",
      workflow_id: id,
      workflow_class: workflow_class,
      by: by,
      paused_duration_seconds: paused_duration
    })

    enqueue_next_steps
  end

  # Get pause metadata
  #
  # @return [Hash, nil] Pause information or nil if never paused
  #
  def pause_metadata
    return nil unless workflow_config["paused_at"]

    {
      paused_at: Time.parse(workflow_config["paused_at"]),
      paused_by: workflow_config["paused_by"],
      pause_reason: workflow_config["pause_reason"],
      resumed_at: workflow_config["resumed_at"] ? Time.parse(workflow_config["resumed_at"]) : nil,
      resumed_by: workflow_config["resumed_by"]
    }
  end

  # Calculate how long workflow was paused (in seconds)
  #
  # @return [Float, nil] Duration in seconds, or nil if not paused
  #
  def paused_duration
    return nil unless workflow_config["paused_at"]

    paused_at = Time.parse(workflow_config["paused_at"])
    resumed_at = workflow_config["resumed_at"] ? Time.parse(workflow_config["resumed_at"]) : Time.current

    (resumed_at - paused_at).to_f
  end
end
