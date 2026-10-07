class CreateLoginTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :login_tokens, id: :uuid do |t|
      t.string :email, null: false
      t.string :token_digest, null: false
      t.string :purpose, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :requested_ip
      t.string :user_agent
      t.timestamps
    end

    add_index :login_tokens, :token_digest, unique: true
    add_index :login_tokens, [ :email, :purpose ], where: "consumed_at IS NULL", name: "index_login_tokens_open_by_email"
    add_index :login_tokens, :expires_at
  end
end
