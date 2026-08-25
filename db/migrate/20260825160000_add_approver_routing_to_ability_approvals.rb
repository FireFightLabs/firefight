class AddApproverRoutingToAbilityApprovals < ActiveRecord::Migration[8.1]
  def up
    add_column :ability_approvals, :approver_ids, :jsonb, null: false, default: []
    add_column :ability_approvals, :notify, :string
    add_column :ability_approvals, :notifications, :jsonb, null: false, default: []

    execute <<~SQL
      UPDATE ability_approvals
      SET notifications = jsonb_build_array(
        jsonb_build_object('channel_id', notification_channel_id, 'message_id', notification_message_id)
      )
      WHERE notification_channel_id IS NOT NULL AND notification_message_id IS NOT NULL
    SQL

    remove_column :ability_approvals, :notification_channel_id
    remove_column :ability_approvals, :notification_message_id
  end

  def down
    add_column :ability_approvals, :notification_channel_id, :string
    add_column :ability_approvals, :notification_message_id, :string

    execute <<~SQL
      UPDATE ability_approvals
      SET notification_channel_id = notifications->0->>'channel_id',
          notification_message_id = notifications->0->>'message_id'
      WHERE jsonb_array_length(notifications) > 0
    SQL

    remove_column :ability_approvals, :notifications
    remove_column :ability_approvals, :notify
    remove_column :ability_approvals, :approver_ids
  end
end
