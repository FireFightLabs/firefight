# An operator's second factor. The secret is encrypted, the recovery codes are kept only as digests, and failed
# attempts are counted here so a lockout holds across every process.
class CreateOperatorCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_credentials, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.text :totp_secret, null: false
      t.datetime :confirmed_at
      t.bigint :last_used_step
      t.string :recovery_code_digests, array: true, null: false, default: []
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.timestamps
    end
  end
end
