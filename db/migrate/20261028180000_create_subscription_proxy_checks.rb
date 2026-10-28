class CreateSubscriptionProxyChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :subscription_proxy_checks, id: :uuid do |t|
      t.string :key, null: false
      t.datetime :checked_at
      t.datetime :failing_since
      t.string :last_error
      t.string :version
      t.timestamps
    end
    add_index :subscription_proxy_checks, :key, unique: true
  end
end
