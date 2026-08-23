# "completed" meant both a 2xx and a 5xx, with the 2xx rule re-derived in
# Ruby and in the React sheet. The outcome is now decided once, where the
# response is known, and stored as succeeded or failed.
class DecideWebhookDeliveryOutcomeAtWriteTime < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE webhook_deliveries
      SET state = CASE
        WHEN state = 'completed' AND error_message IS NULL AND response_code BETWEEN 200 AND 299 THEN 'succeeded'
        WHEN state IN ('completed', 'errored') THEN 'failed'
        ELSE state
      END
    SQL
    execute "UPDATE webhook_deliveries SET delivered_at = NULL WHERE state = 'failed'"
  end

  def down
    execute <<~SQL
      UPDATE webhook_deliveries
      SET state = CASE
        WHEN state = 'succeeded' THEN 'completed'
        WHEN state = 'failed' AND response_code IS NOT NULL THEN 'completed'
        WHEN state = 'failed' THEN 'errored'
        ELSE state
      END
    SQL
  end
end
