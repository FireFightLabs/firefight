# Runs a trigger would have started past the workflow's most runs an hour, counted by the hour they were skipped in, so
# its page says how many and when rather than dropping them unseen. Counted in one statement, so skips at once each
# count.
class Workflow::SkippedRun < ApplicationRecord
  self.table_name = "workflow_skipped_runs"

  # How far back the workflow's page shows them. Anything older is let go (WorkflowRunRetentionJob).
  SHOWN_FOR = 1.week
  SHOWN_LIMIT = 48

  belongs_to :workflow, inverse_of: :skipped_runs

  scope :recent, ->(now = Time.current) { where(hour: (now - SHOWN_FOR)..).order(hour: :desc).limit(SHOWN_LIMIT) }

  def self.count!(workflow, at: Time.current)
    sql = <<~SQL.squish
      INSERT INTO workflow_skipped_runs (id, workflow_id, hour, count, last_at, created_at, updated_at)
      VALUES (gen_random_uuid(), :workflow_id, :hour, 1, :at, :at, :at)
      ON CONFLICT (workflow_id, hour)
      DO UPDATE SET count = workflow_skipped_runs.count + 1, last_at = GREATEST(workflow_skipped_runs.last_at, EXCLUDED.last_at), updated_at = EXCLUDED.updated_at
    SQL
    with_connection { |connection| connection.exec_update(sanitize_sql_array([ sql, { workflow_id: workflow.id, hour: at.beginning_of_hour, at: at } ])) }
  end

  def self.prune!(now = Time.current) = where(hour: ...(now - SHOWN_FOR)).delete_all
end
