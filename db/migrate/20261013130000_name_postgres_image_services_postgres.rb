# A repository's setup read from CI named a Postgres image's service after the image, such as pgvector for
# pgvector/pgvector:pg18. A sandbox that cannot run images starts only a service called postgres, so it started no
# database at all for those setups. Each such service is renamed postgres, unless its setup already has one.
class NamePostgresImageServicesPostgres < ActiveRecord::Migration[8.1]
  POSTGRES_IMAGES = %w[postgresql pgvector postgis timescaledb timescaledb-ha citus paradedb pgrouting].freeze

  class Setup < ActiveRecord::Base
    self.table_name = "repository_setups"
  end

  def up
    Setup.find_each do |setup|
      services = Array(setup.services)
      next if services.any? { |service| service["name"] == "postgres" }

      renamed = services.map { |service| POSTGRES_IMAGES.include?(service["name"]) ? service.merge("name" => "postgres") : service }
      next if renamed == services || renamed.count { |service| service["name"] == "postgres" } > 1

      setup.update_columns(services: renamed)
    end
  end

  # The name each service had came from its image, and the setup is read from CI again whenever an admin asks.
  def down; end
end
