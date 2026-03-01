module SolidWorkflow
  class Step < Record
    module Statusable
      extend ActiveSupport::Concern

      included do
        enum :status, {
          pending: "pending",
          running: "running",
          succeeded: "succeeded",
          failed: "failed",
          skipped: "skipped",
          cancelled: "cancelled"
        }

        scope :pending, -> { where(status: :pending) }
        scope :running, -> { where(status: :running) }
        scope :completed, -> { where(status: %i[succeeded skipped]) }
        scope :failed, -> { where(status: :failed) }
        scope :in_progress, -> { where(status: :running) }
        scope :orphaned, ->(threshold = 10.minutes.ago) { running.where("updated_at < ?", threshold) }
      end

      def completed?
        succeeded? || failed? || skipped? || cancelled?
      end
    end
  end
end
