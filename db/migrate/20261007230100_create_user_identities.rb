class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.boolean :email_verified, null: false, default: false
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :user_identities, [ :provider, :uid ], unique: true
  end
end
