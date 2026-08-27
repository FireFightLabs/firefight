# These tables were dumped into schema.rb without a migration and were never
# used by the app, so schema:load and migrate produced different databases.
class DropUnusedCatalogTables < ActiveRecord::Migration[8.1]
  TABLES = %i[
    service_dependencies service_environments service_product_areas
    team_product_areas team_services
    services teams product_areas environments
  ].freeze

  def up
    TABLES.each { |table| drop_table table, if_exists: true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
