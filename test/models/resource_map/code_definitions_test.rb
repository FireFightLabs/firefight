require "test_helper"

class ResourceMap::CodeDefinitionsTest < ActiveSupport::TestCase
  File = Integrations::Packs::Github::Infrastructure::File

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = connection("github")
    @northflank = connection("northflank")
    cloudflare = connection("cloudflare")
    ResourceMap.record!(@github, ResourceMap::Snapshot.new(resources: [ repository("acme/infra"), repository("acme/web") ]))
    ResourceMap.record!(@northflank, ResourceMap::Snapshot.new(resources: [
      found("northflank", ResourceMap::KIND_SERVICE, "web"), found("northflank", ResourceMap::KIND_SERVICE, "billing-api"),
      found("northflank", ResourceMap::KIND_SERVICE, "true"), found("northflank", ResourceMap::KIND_SERVICE, "spec")
    ]))
    ResourceMap.record!(cloudflare, ResourceMap::Snapshot.new(resources: [ ResourceMap.domain("app.acme.com"), found("cloudflare", ResourceMap::KIND_WORKER, "edge-api") ]))
  end

  test "a resource named in an infrastructure file is suggested as managed in its repository, surer beside its provider, with a link to the file" do
    record!([
      file("dns.tf", "Terraform", %(resource "cloudflare_record" "app" {\n  name = "app.acme.com"\n})),
      file("api.tf", "Terraform", %(resource "northflank_service" "billing" {\n  name = "billing-api"\n})),
      file("wrangler.toml", "Wrangler", %(name = "edge-api"))
    ])

    links = managed.to_h { |link| [ link.from_resource.name, [ link.certainty, link.clues ] ] }
    assert_equal [ ResourceMap::CERTAINTY_LIKELY, [ "Named in dns.tf (Terraform) https://github.com/acme/infra/blob/main/dns.tf" ] ], links["app.acme.com"]
    assert_equal [ ResourceMap::CERTAINTY_LIKELY, [ "Named in api.tf (Terraform), beside its provider https://github.com/acme/infra/blob/main/api.tf" ] ], links["billing-api"]
    assert_equal ResourceMap::CERTAINTY_POSSIBLE, links["edge-api"].first
  end

  test "only values name a resource, never keys or words every config uses, and a hostname only called from a file is a maybe" do
    record!([ file("deploy/web.yaml", "Kubernetes", "kind: Deployment\nspec:\n  replicas: 2\n  paused: true\n"),
              file("wrangler.toml", "Wrangler", %([vars]\nAPI_URL = "https://app.acme.com/v1")) ])

    assert_equal [ [ "app.acme.com", ResourceMap::CERTAINTY_POSSIBLE ] ], managed.map { |link| [ link.from_resource.name, link.certainty ] }
  end

  test "a generic or short name only counts beside its provider, and a provider named far away does not count" do
    record!([ file("deploy/web.yaml", "Kubernetes", "kind: Service\nmetadata:\n  name: web") ])
    assert_empty managed

    record!([ file("main.tf", "Terraform", %(resource "northflank_service" "web" {\n  name = "web"\n})) ])
    assert_equal [ "web" ], managed.map { |link| link.from_resource.name }

    far = %(# northflank\n#{"\n" * 30}name = "billing-api")
    record!([ file("main.tf", "Terraform", far) ])
    assert_equal [ [ "billing-api", ResourceMap::CERTAINTY_POSSIBLE ] ], managed.map { |link| [ link.from_resource.name, link.certainty ] }
  end

  test "a suggestion keeps its id while it holds, a partial read never takes one away, and one a person dismissed stays dismissed" do
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])
    first = managed.sole.id

    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])
    assert_equal first, managed.sole.id

    ResourceMap::CodeDefinitions.new(@workspace).record!(@github, [], read_in_full: [ "acme/web" ])
    assert_equal first, managed.sole.id, "acme/infra was not read in full this time"

    ResourceMap::Link.find(first).dismiss!
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])
    assert_equal [ first ], ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_MANAGED_BY).pluck(:id)

    ResourceMap::Link.find(first).destroy!
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])
    record!([])
    assert_empty managed
  end

  test "a suggestion left by a removed connection is taken up by the next one to read the file" do
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])
    first = managed.sole
    @github.integration.destroy!
    assert_nil first.reload.integration_environment_id

    other = connection("github", slug: "github_two")
    ResourceMap::CodeDefinitions.new(@workspace).record!(other, [ file("dns.tf", "Terraform", %(name = "app.acme.com")) ], read_in_full: [ "acme/infra" ])

    assert_equal [ [ first.id, other.id ] ], managed.map { |link| [ link.id, link.integration_environment_id ] }
  end

  test "the matcher run after every sweep leaves these suggestions alone" do
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")) ])

    ResourceMap::Matcher.new(@workspace).run!

    assert_equal 1, managed.size
  end

  test "being managed in a repository is not something that fails with it, and the walk from a resource stops at its repository" do
    record!([ file("dns.tf", "Terraform", %(name = "app.acme.com")), file("api.tf", "Terraform", %(northflank_service "billing-api")) ])
    managed.each { |link| link.confirm!(by: nil) }

    row = ResourceMap::View.new(@workspace).rows.find { |each| each.resource.name == "acme/infra" }
    assert_empty row.dependent_ids
    walked = ResourceMap::Resource.find_by!(workspace: @workspace, name: "app.acme.com").neighborhood.map { |link, _| link.from_resource.name }
    assert_not_includes walked, "billing-api"
  end

  private

  def connection(provider, slug: provider)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: slug.humanize, slug: slug).integration_environments.create!
  end

  def record!(files) = ResourceMap::CodeDefinitions.new(@workspace).record!(@github, files, read_in_full: [ "acme/infra" ])

  def repository(name) = ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: name, name: name)

  def found(provider, kind, name) = ResourceMap::Found.new(provider: provider, account: "acme", kind: kind, external_id: name, name: name)

  def file(path, tool, content) = File.new(repository: "acme/infra", path: path, tool: tool, content: content, url: "https://github.com/acme/infra/blob/main/#{path}")

  def managed = ResourceMap::Link.standing.where(workspace: @workspace, relation: ResourceMap::RELATION_MANAGED_BY).includes(:from_resource).order(:id).to_a
end
