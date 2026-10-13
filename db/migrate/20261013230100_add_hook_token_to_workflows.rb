# Each workflow gets an address of its own that a signed POST starts it at, named by an unguessable token.
class AddHookTokenToWorkflows < ActiveRecord::Migration[8.1]
  def up
    add_column :workflows, :hook_token, :string
    execute <<~SQL.squish
      UPDATE workflows SET hook_token = translate(encode(gen_random_bytes(24), 'base64'), '+/=', '-_')
    SQL
    change_column_null :workflows, :hook_token, false
    add_index :workflows, :hook_token, unique: true
  end

  def down
    remove_index :workflows, :hook_token
    remove_column :workflows, :hook_token
  end
end
