# A workflow's Send webhook step sends a delivery of its own data through an outbound webhook, so a delivery is about an
# incident's event or a workflow run.
class LetWorkflowsSendWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    change_column_null :webhook_deliveries, :incident_event_id, true
    add_reference :webhook_deliveries, :workflow_run, type: :uuid, foreign_key: { to_table: :workflow_runs, on_delete: :nullify }, index: true
  end
end
