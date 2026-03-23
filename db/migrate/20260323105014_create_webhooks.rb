class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhooks, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.text :url, null: false
      t.string :signing_secret, null: false
      t.jsonb :subscribed_events, default: [], null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :webhooks, [ :workspace_id, :active ]
  end
end
