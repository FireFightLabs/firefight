module SolidWorkflow
  class CleanupJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    RETENTION = 30.days
    BATCH_SIZE = 500
    BATCH_PAUSE = 0.1

    def perform(retention: RETENTION, batch_size: BATCH_SIZE)
      cutoff = retention.ago
      total = 0

      loop do
        ids = SolidWorkflow::Workflow
          .completed
          .where("completed_at < ? OR (completed_at IS NULL AND updated_at < ?)", cutoff, cutoff)
          .limit(batch_size)
          .pluck(:id)
        break if ids.empty?

        deleted = SolidWorkflow::Workflow.where(id: ids).delete_all
        total += deleted
        sleep BATCH_PAUSE
      end

      Rails.logger.info({
        event:      "workflow.cleanup.completed",
        deleted:    total,
        cutoff:     cutoff.iso8601,
        retention_days: retention.to_i / 86_400
      })
    end
  end
end
