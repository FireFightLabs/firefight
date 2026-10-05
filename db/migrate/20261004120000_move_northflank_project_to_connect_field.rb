# Northflank's project is not a secret, so it moved from a connection's encrypted credentials to its connect fields,
# where the connection's card shows it. Each Northflank environment row's project moves across, and the credentials keep
# only the token.
class MoveNorthflankProjectToConnectField < ActiveRecord::Migration[8.1]
  PROVIDER = "northflank".freeze
  PROJECT = "project".freeze

  def up
    rows.find_each do |row|
      credentials = row.credentials_hash
      project = credentials.delete(PROJECT).to_s.strip
      next if project.empty?

      row.update!(credentials: credentials.to_json, base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.merge(PROJECT => project)))
    end
  end

  def down
    rows.find_each do |row|
      project = row.fields[PROJECT]
      next if project.blank?

      row.update!(credentials: row.credentials_hash.merge(PROJECT => project).to_json,
                  base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.except(PROJECT)))
    end
  end

  private

  def rows = IntegrationEnvironment.joins(:integration).where(integrations: { provider: PROVIDER })
end
