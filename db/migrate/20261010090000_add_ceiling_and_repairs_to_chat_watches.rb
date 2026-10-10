class AddCeilingAndRepairsToChatWatches < ActiveRecord::Migration[8.1]
  def change
    change_table :chat_watches, bulk: true do |t|
      t.integer :reads_per_hour, null: false, default: 120
      t.integer :reads_total, null: false, default: 0
      t.integer :reads_this_hour, null: false, default: 0
      t.datetime :hour_began_at
      t.datetime :next_check_at
      t.datetime :ceiling_told_at
    end

    change_table :chat_watch_steps, bulk: true do |t|
      t.integer :repairs, null: false, default: 0
      t.text :repair_reason
      t.datetime :repaired_at
      t.datetime :read_at
      t.datetime :judged_at
      t.datetime :steady_since
    end
  end
end
