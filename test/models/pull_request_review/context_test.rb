require "test_helper"

# A review starts from where its repository runs on the map, what depends on it and the incidents on those services.
class PullRequestReview::ContextTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    build_two_environment_map(@workspace)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    row = github.integration_environments.create!(environment: catalog_entries(:production_env))
    repository = ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/api", name: "acme/api",
                                        status: nil, url: "https://github.com/acme/api")
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ repository ], links: [], gaps: []))
    @resource = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "acme/api")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @resource)
    @incident = incidents(:active_critical_ws1)
    @incident.update!(custom_fields: { "affected_services" => [ catalog_entries(:auth_service).id ] })
    @review = PullRequestReview.create!(workspace: @workspace, repository: "ACME/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
  end

  test "the repository on the map, the services it runs and the incidents on them, within what Halon may read" do
    context = PullRequestReview::Context.new(@review, SystemAgent.investigator)
    sections = context.sections

    assert_equal @resource, context.resource
    assert_includes sections["Where this repository runs"], "resource #{@resource.id}"
    assert_includes sections["Past incidents on these services"], "#{@incident.identifier} #{@incident.name}"
    assert_equal [ catalog_entries(:auth_service) ], context.services.map(&:entry)
  end

  test "a repository the map does not hold says so, and so does a service with no incidents" do
    @review.update!(repository: "acme/other")
    sections = PullRequestReview::Context.new(@review, SystemAgent.investigator).sections

    assert_equal "The resource map does not hold acme/other, so where it runs is not known.", sections["Where this repository runs"]
    assert_equal "The map holds nothing that depends on this repository.", sections["What depends on it"]
    assert_equal "No past incidents are recorded on these services.", sections["Past incidents on these services"]
  end
end
