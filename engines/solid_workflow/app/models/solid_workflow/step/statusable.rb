module SolidWorkflow
  class Step < Record
    module Statusable
      extend ActiveSupport::Concern

      included do
        enum :status, {
          pending: "pending",
          running: "running",
          waiting: "waiting",
          succeeded: "succeeded",
          failed: "failed",
          skipped: "skipped",
          bypassed: "bypassed",
          cancelled: "cancelled"
        }

        scope :pending, -> { where(status: :pending) }
        scope :running, -> { where(status: :running) }
        scope :failed, -> { where(status: :failed) }
        scope :waiting, -> { where(status: :waiting) }
        # Waiting steps whose time came, or that were sent their signal while their run could not move.
        scope :due, -> { waiting.where("run_at <= ? OR signal_payload IS NOT NULL", Time.current) }
        scope :past_timeout, -> { running.where(timeout_at: ..Time.current) }
        scope :orphaned, ->(threshold = SolidWorkflow.orphaned_step_threshold.ago) { running.where("updated_at < ?", threshold) }
      end

      def completed?
        succeeded? || failed? || skipped? || bypassed? || cancelled?
      end

      # Failed, and set to carry on or take its error route, so the run does not fail with it.
      def failure_tolerated?
        failed? && SolidWorkflow::Definition::TOLERATED_FAILURES.include?(on_failure)
      end
    end
  end
end
