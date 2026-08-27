class AddOnBehalfOfToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_keys, :workspace_membership, type: :uuid, null: true,
                  foreign_key: true, index: true
  end
end
