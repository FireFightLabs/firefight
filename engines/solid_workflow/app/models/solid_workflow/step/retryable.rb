module SolidWorkflow
  class Step < Record
    module Retryable
      extend ActiveSupport::Concern

      BACKOFF_EXPONENTIAL = "exponential"
      BACKOFF_LINEAR = "linear"
      BACKOFF_FIXED = "fixed"

      # Retrying these is pointless — the next attempt produces the same
      # outcome. Engine surfaces them as terminal so callers see the real
      # cause instead of a generic max-attempts exhaustion.
      TERMINAL_ERROR_CLASSES = %w[
        ActiveRecord::RecordNotFound
        ActiveRecord::RecordInvalid
        ArgumentError
        NoMethodError
        TypeError
        AdapterError::AuthRevoked
        AdapterError::UnsafeDownloadHost
        AdapterError::RestrictedAction
      ].freeze

      def should_retry?
        return false if terminal_error?
        attempts < max_attempts
      end

      def terminal_error?
        return false if last_error.blank?
        TERMINAL_ERROR_CLASSES.any? { |klass| last_error.start_with?("#{klass}:") }
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

          workflow.record_event(SolidWorkflow::Events::Step::MANUAL_SKIP, step: self, reason: reason)
        end

        workflow.enqueue_next_steps
      end

      private

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
