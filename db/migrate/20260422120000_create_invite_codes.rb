class CreateInviteCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :invite_codes, id: :uuid do |t|
      t.string :code_digest, null: false
      t.datetime :expires_at
      t.datetime :redeemed_at
      t.references :redeemed_by, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :invite_codes, :code_digest, unique: true
  end
end
