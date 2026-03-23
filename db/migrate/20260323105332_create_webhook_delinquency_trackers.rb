class CreateWebhookDelinquencyTrackers < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_delinquency_trackers, id: :uuid do |t|
      t.references :webhook, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.integer :consecutive_failures_count, default: 0, null: false
      t.datetime :first_failure_at
      t.timestamps
    end
  end
end
