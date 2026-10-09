# A session follows its pull request through the connection it was opened with, so a removed connection leaves it with
# none rather than pointing at nothing.
class AddIntegrationEnvironmentForeignKeyToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE code_agent_sessions SET integration_environment_id = NULL
      WHERE integration_environment_id IS NOT NULL AND integration_environment_id NOT IN (SELECT id FROM integration_environments)
    SQL
    add_foreign_key :code_agent_sessions, :integration_environments, on_delete: :nullify
  end

  def down
    remove_foreign_key :code_agent_sessions, :integration_environments
  end
end
