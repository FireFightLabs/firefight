# A Northflank or Railway connection now reads one, several or every project its token can read, so the project connect
# field holds a list. Each environment row's one project becomes a list of it, and reads exactly as before.
class KeepNorthflankAndRailwayProjectsAsLists < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[northflank railway].freeze
  PROJECT = "project".freeze

  def up
    rows.find_each do |row|
      project = row.fields[PROJECT]
      next unless project.is_a?(String)

      store(row, project.strip.presence && [ project.strip ])
    end
  end

  def down
    rows.find_each do |row|
      projects = row.fields[PROJECT]
      next unless projects.is_a?(Array)

      store(row, projects.first)
    end
  end

  private

  def rows = IntegrationEnvironment.joins(:integration).where(integrations: { provider: PROVIDERS })

  def store(row, value)
    row.update_columns(base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.merge(PROJECT => value).compact))
  end
end
