class AddHealthErrorToIntegrationEnvironments < ActiveRecord::Migration[8.1]
  def change
    add_column :integration_environments, :health_error, :string
  end
end
