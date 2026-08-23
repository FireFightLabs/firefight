module SolidWorkflow
  class Step < Record
    module Retryable
      extend ActiveSupport::Concern

      BACKOFF_EXPONENTIAL = "exponential"
      BACKOFF_LINEAR = "linear"
      BACKOFF_FIXED = "fixed"

      def should_retry?
        return false if terminal_error?
        attempts < max_attempts
      end

      # Terminal errors are never retried, the next attempt produces the
      # same outcome. The class list is engine config so host apps register
      # their own (see SolidWorkflow.terminal_error_classes).
      def terminal_error?
        return false if last_error.blank?
        SolidWorkflow.terminal_error_classes.any? { |klass| last_error.start_with?("#{klass}:") }
      end

      def schedule_retry!
        delay = calculate_backoff

        update!(
          status: :pending,
          run_at: Time.current + delay
        )

        workflow.record_event(SolidWorkflow::Events::Step::RETRY_SCHEDULED, step: self, delay: delay, attempt: attempts)
      end

      def retry_now!
        transaction do
          update!(
            status: :pending,
            attempts: 0,
            last_error: nil,
            run_at: nil
          )

          revive_workflow!
          workflow.record_event(SolidWorkflow::Events::Step::MANUAL_RETRY, step: self)
        end

        workflow.enqueue_next_steps
      end

      def skip!(reason:)
        transaction do
          update!(
            status: :skipped,
            skip_reason: reason,
            completed_at: Time.current
          )

          revive_workflow!
          workflow.record_event(SolidWorkflow::Events::Step::MANUAL_SKIP, step: self, reason: reason)
        end

        workflow.enqueue_next_steps
      end

      private

      # Manual retry/skip on a step of a failed workflow must bring the
      # workflow back to running, otherwise orchestration short-circuits on
      # completed? and the step sits pending forever. Siblings cancelled by
      # the failure go back to pending so the revived run can complete.
      def revive_workflow!
        return unless workflow.transition!(:running, from: :failed)

        SolidWorkflow::Step.where(workflow_id: workflow.id, status: :cancelled).where.not(id: id).update_all(
          status: :pending,
          completed_at: nil,
          updated_at: Time.current
        )

        workflow.record_event(SolidWorkflow::Events::Workflow::RUNNING, reason: "step_recovery")
      end

      def calculate_backoff
        strategy = retry_config&.dig("backoff") || BACKOFF_EXPONENTIAL

        base = case strategy
        when BACKOFF_EXPONENTIAL
          [ 2**attempts, 300 ]
        when BACKOFF_LINEAR
          [ attempts * 30, 300 ]
        when BACKOFF_FIXED
          retry_config["backoff_seconds"] || 60
        else
          60
        end

        base = base.is_a?(Array) ? base.min : base
        # ±25% jitter so a fleet of steps that fail at the same instant
        # don't all retry at the same instant.
        jittered = base + (rand - 0.5) * base * 0.5
        jittered.clamp(1.0, 300.0).seconds
      end
    end
  end
end
