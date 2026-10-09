# What each sandbox provider reports it holds for Firefight, its boxes and its kept copies, as the sweep last read it.
# A row the provider stops reporting gets gone_at. Each provider's last read, and why it failed, is kept beside them.
class CreateProviderSandboxes < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_sandboxes, id: :uuid do |t|
      t.string :provider, null: false
      t.string :kind, null: false
      t.string :purpose
      t.string :ref, null: false
      t.string :name
      t.string :state
      t.string :phase
      t.string :size
      t.datetime :started_at
      t.datetime :provider_updated_at
      t.bigint :byte_size
      t.bigint :monthly_micros
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :gone_at
      t.timestamps
    end
    add_index :provider_sandboxes, [ :provider, :kind, :ref ], unique: true
    add_index :provider_sandboxes, :gone_at

    create_table :sandbox_provider_reads, id: :uuid do |t|
      t.string :provider, null: false, index: { unique: true }
      t.datetime :read_at, null: false
      t.text :error
      t.timestamps
    end
  end
end
