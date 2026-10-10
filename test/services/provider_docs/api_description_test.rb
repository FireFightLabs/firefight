require "test_helper"

class ProviderDocs::ApiDescriptionTest < ActiveSupport::TestCase
  ADDRESS = "https://specs.example.com/api.json".freeze

  test "an OpenAPI description's GETs are written by area, with their parameters and answers, and nothing that changes" do
    spec = {
      "openapi" => "3.0.0", "info" => { "title" => "Acme API" }, "servers" => [ { "url" => "https://api.acme.test/v1" } ],
      "paths" => {
        "/services/{id}/deploys" => {
          "parameters" => [ { "$ref" => "#/components/parameters/id" } ],
          "get" => { "tags" => [ "Deploys" ], "summary" => "List deploys", "description" => "<p>Newest first.</p>",
                     "parameters" => [ { "name" => "limit", "in" => "query", "schema" => { "type" => "integer" } },
                                       { "name" => "Authorization", "in" => "header" } ],
                     "responses" => { "200" => { "content" => { "application/json" => { "schema" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Deploy" } } } } } } },
          "post" => { "tags" => [ "Deploys" ], "summary" => "Start a deploy" }
        },
        "/watch/services" => { "get" => { "tags" => [ "Deploys" ], "summary" => "Watch" } }
      },
      "components" => {
        "parameters" => { "id" => { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "string" } } },
        "schemas" => { "Deploy" => { "properties" => { "id" => { "type" => "string" }, "status" => { "type" => "string", "enum" => %w[live failed] } } } }
      }
    }

    source = ProviderDocs::Sync.run!(definition("openapi", "leave_out" => [ "/watch/" ]), client: ProviderDocsHelper::FakeWeb.new(ADDRESS => spec.to_json))

    assert_equal %w[api/deploys.md api/index.md], ProviderDocPage.paths_of("render").sort
    index = ProviderDocPage.named("render", "api/index.md").content
    assert_includes index, "Every path is a GET to https://api.acme.test/v1."
    assert_includes index, "- GET /services/{id}/deploys: List deploys"
    page = ProviderDocPage.named("render", "api/deploys.md").content
    assert_includes page, "## GET /services/{id}/deploys"
    assert_includes page, "Newest first."
    assert_includes page, "- id (string, required)"
    assert_includes page, "- limit (integer)"
    assert_includes page, "Answers: id (string), status (string, one of live, failed)"
    assert_not_includes page, "Start a deploy"
    assert_not_includes page, "Authorization"
    assert_not_includes index, "/watch/"
    assert_equal "Licensed words.", source.license
  end

  test "a description that did not change keeps its pages without writing them again" do
    spec = { "swagger" => "2.0", "host" => "api.acme.test", "basePath" => "/api/v4",
             "paths" => { "/api/v4/projects" => { "get" => { "operationId" => "listProjects" } } } }.to_json
    ProviderDocs::Sync.run!(definition("openapi", "relative_to" => "/api/v4"), client: ProviderDocsHelper::FakeWeb.new(ADDRESS => spec))
    kept = ProviderDocPage.named("render", "api/projects.md")
    assert_includes kept.content, "## GET /projects"

    web = ProviderDocsHelper::FakeWeb.new(ADDRESS => :unchanged)
    ProviderDocs::Sync.run!(definition("openapi", "relative_to" => "/api/v4"), client: web)

    assert_equal %w[api/index.md api/projects.md], ProviderDocPage.paths_of("render").sort
    assert_equal kept.updated_at, kept.reload.updated_at
  end

  test "a Discovery document's GET methods are written by resource, a botocore description's reads by name, and a GraphQL schema's queries by type" do
    discovery = { "title" => "Cloud Run Admin API", "version" => "v2", "rootUrl" => "https://run.googleapis.com/", "servicePath" => "",
                  "resources" => { "projects" => { "resources" => { "services" => { "methods" => {
                    "list" => { "id" => "run.projects.services.list", "httpMethod" => "GET", "flatPath" => "v2/projects/{projectsId}/services",
                                "parameters" => { "pageSize" => { "location" => "query", "type" => "integer" } } },
                    "delete" => { "id" => "run.projects.services.delete", "httpMethod" => "DELETE", "flatPath" => "v2/projects/{projectsId}/services/{s}" }
                  } } } } } }
    ProviderDocs::Sync.run!(definition("discovery", provider: "google_cloud"), client: ProviderDocsHelper::FakeWeb.new(ADDRESS => discovery.to_json))
    page = ProviderDocPage.named("google_cloud", "api/projects-services.md").content
    assert_includes page, "## GET /v2/projects/{projectsId}/services"
    assert_includes page, "- pageSize (integer)"
    assert_not_includes page, "delete"

    botocore = { "metadata" => { "serviceFullName" => "Amazon ECS", "endpointPrefix" => "ecs" },
                 "operations" => { "DescribeServices" => { "name" => "DescribeServices", "input" => { "shape" => "In" }, "documentation" => "<p>Describes services.</p>" },
                                   "UpdateService" => { "name" => "UpdateService" } },
                 "shapes" => { "In" => { "type" => "structure", "required" => [ "services" ], "members" => { "services" => { "shape" => "L" }, "DBInstanceIdentifier" => { "shape" => "S" } } },
                               "L" => { "type" => "list" }, "S" => { "type" => "string" } } }
    ProviderDocs::Sync.run!(definition("botocore", provider: "aws", "service" => "ecs"), client: ProviderDocsHelper::FakeWeb.new(ADDRESS => botocore.to_json))
    page = ProviderDocPage.named("aws", "api/ecs.md").content
    assert_includes page, "## DescribeServices (describe_services)"
    assert_includes page, "- services (list, required)"
    assert_includes page, "- db_instance_identifier (string)"
    assert_not_includes page, "UpdateService"

    named = ->(name, kind = "OBJECT") { { "kind" => kind, "name" => name } }
    graphql = { "data" => { "__schema" => { "queryType" => { "name" => "Query" }, "mutationType" => { "name" => "Mutation" }, "types" => [
      { "name" => "Query", "fields" => [ { "name" => "deployment", "args" => [ { "name" => "id", "type" => { "kind" => "NON_NULL", "ofType" => named.("String", "SCALAR") } } ],
                                           "type" => { "kind" => "NON_NULL", "ofType" => named.("Deployment") } } ] },
      { "name" => "Mutation", "fields" => [ { "name" => "deploymentRedeploy", "args" => [], "type" => named.("Deployment") } ] },
      { "name" => "Deployment", "fields" => [ { "name" => "status", "type" => named.("DeploymentStatus", "ENUM") } ] }
    ] } } }
    ProviderDocs::Sync.run!(definition("graphql", provider: "railway"), client: ProviderDocsHelper::FakeWeb.new(ADDRESS => graphql.to_json))
    page = ProviderDocPage.named("railway", "api/deployment.md").content
    assert_includes page, "## query deployment"
    assert_includes page, "- id (String!, required)"
    assert_includes page, "Answers: status (DeploymentStatus)"
    assert_not_includes page, "deploymentRedeploy"
  end

  test "a description split over several files is written as one" do
    other = "https://specs.example.com/databases.json"
    shared = { "$ref" => "../../../common-types/resource-management/v5/types.json#/parameters/ApiVersionParameter" }
    servers = { "swagger" => "2.0", "info" => { "version" => "2025-01-01" },
                "paths" => { "/servers" => { "get" => { "tags" => [ "Servers" ], "operationId" => "Servers_List", "parameters" => [ shared ] } } } }
    databases = { "swagger" => "2.0", "paths" => { "/databases" => { "get" => { "tags" => [ "Databases" ], "operationId" => "Databases_List" } } } }
    web = ProviderDocsHelper::FakeWeb.new(ADDRESS => servers.to_json, other => databases.to_json)

    ProviderDocs::Sync.run!(definition("openapi", provider: "azure", "api" => [ ADDRESS, other ]), client: web)

    index = ProviderDocPage.named("azure", "api/index.md").content
    assert_includes index, "- GET /servers: Servers_List"
    assert_includes index, "- GET /databases: Databases_List"
    assert_includes ProviderDocPage.named("azure", "api/servers.md").content, "- api-version (string, one of 2025-01-01, required)"
  end

  test "a source naming an api is the api kind, and holds the pages under its endpoints folder" do
    source = definition("openapi")

    assert source.could_hold?("api/index.md")
    assert source.could_hold?("api/deploys.md")
    assert_not source.could_hold?("other/index.md")
    assert_equal [ "api/" ], source.roots
  end

  private

  def definition(format, provider: "render", **settings)
    ProviderDocSource::Definition.new(key: "#{provider}_api", provider: provider, kind: ProviderDocSource::Definition::KIND_API,
                                      settings: { "api" => ADDRESS, "format" => format, "license" => "Licensed words.", "endpoints" => "api" }.merge(settings))
  end
end
