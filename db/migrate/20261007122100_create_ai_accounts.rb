class CreateAiAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_accounts, id: :uuid do |t|
      t.string :provider, null: false
      t.datetime :out_of_credit_since
      t.datetime :balance_checked_at
      t.timestamps
    end
    add_index :ai_accounts, :provider, unique: true
  end
end
