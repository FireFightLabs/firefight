class AddOutOfCreditAlertedAtToAiAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_accounts, :out_of_credit_alerted_at, :datetime
  end
end
