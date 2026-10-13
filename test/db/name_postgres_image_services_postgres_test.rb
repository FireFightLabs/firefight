require "test_helper"
require Rails.root.join("db/migrate/20261013130000_name_postgres_image_services_postgres")

class NamePostgresImageServicesPostgresTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
  end

  test "a service read from a Postgres image built around an extension becomes postgres, unless the setup already names one" do
    vector = setup_with("acme/api", [ { "name" => "pgvector", "image" => "pgvector/pgvector:pg18", "port" => 5432, "env" => { "POSTGRES_USER" => "postgres" } },
                                      { "name" => "redis", "image" => "redis:7", "env" => {} } ])
    both = setup_with("acme/geo", [ { "name" => "postgres", "image" => "postgres:16", "env" => {} }, { "name" => "postgis", "image" => "postgis/postgis:16-3.4", "env" => {} } ])
    other = setup_with("acme/files", [ { "name" => "minio", "image" => "minio/minio:latest", "env" => {} } ])

    ActiveRecord::Migration.suppress_messages { NamePostgresImageServicesPostgres.new.migrate(:up) }

    assert_equal [ { "name" => "postgres", "image" => "pgvector/pgvector:pg18", "port" => 5432, "env" => { "POSTGRES_USER" => "postgres" } },
                   { "name" => "redis", "image" => "redis:7", "env" => {} } ], vector.reload.services
    assert_equal [ "postgres", "postgis" ], both.reload.services.pluck("name"), "a setup with its own postgres keeps both as they were"
    assert_equal [ "minio" ], other.reload.services.pluck("name")
  end

  private

  def setup_with(repository, services)
    RepositorySetup.create!(workspace: @workspace, integration: @integration, repository: repository, services: services, derived_from: ".github/workflows/ci.yml, job test")
  end
end
