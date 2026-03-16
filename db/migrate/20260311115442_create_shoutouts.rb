class CreateShoutouts < ActiveRecord::Migration[8.1]
  def change
    create_table :shoutouts, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :from_member_id, null: false
      t.uuid :to_member_id, null: false
      t.text :message, null: false
      t.string :slack_message_ts

      t.timestamps

      t.index :incident_id
    end

    add_foreign_key :shoutouts, :incidents
    add_foreign_key :shoutouts, :workspace_memberships, column: :from_member_id
    add_foreign_key :shoutouts, :workspace_memberships, column: :to_member_id
  end
end
