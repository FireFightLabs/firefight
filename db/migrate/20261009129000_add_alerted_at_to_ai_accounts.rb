class AddAlertedAtToAiAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_accounts, :alerted_at, :datetime
  end
end
