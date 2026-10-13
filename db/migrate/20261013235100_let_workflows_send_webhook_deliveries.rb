# A workflow's Send webhook step sends a delivery of its own data through an outbound webhook, so a delivery is about an
# incident's event or a workflow run. Going back drops the deliveries workflows sent, since they name no incident event.
class LetWorkflowsSendWebhookDeliveries < ActiveRecord::Migration[8.1]
  def up
    change_column_null :webhook_deliveries, :incident_event_id, true
    add_reference :webhook_deliveries, :workflow_run, type: :uuid, foreign_key: { to_table: :workflow_runs, on_delete: :nullify }, index: true
  end

  def down
    execute "DELETE FROM webhook_deliveries WHERE incident_event_id IS NULL"
    remove_reference :webhook_deliveries, :workflow_run, foreign_key: { to_table: :workflow_runs }, index: true
    change_column_null :webhook_deliveries, :incident_event_id, false
  end
end
