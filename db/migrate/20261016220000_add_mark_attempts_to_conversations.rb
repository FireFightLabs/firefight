class AddMarkAttemptsToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :mark_attempts, :jsonb, default: {}, null: false
  end
end
