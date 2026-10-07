class AddInstallationStateToIntegrationEnvironments < ActiveRecord::Migration[8.1]
  def change
    # What the provider last said of the app installation a connection was made through: whether it was removed,
    # suspended or shares nothing, when that was seen, and the account, its settings page and what it was granted.
    add_column :integration_environments, :installation_state, :string
    add_column :integration_environments, :installation_state_at, :datetime
    add_column :integration_environments, :installation_details, :jsonb, default: {}, null: false
  end
end
