require "test_helper"

class ResourceMapTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = connection("northflank")
  end

  test "a sweep puts what the connection reaches on the map, with the links it declares" do
    ResourceMap.record!(@row, snapshot(web, repository, links: [ link(web, repository, ResourceMap::RELATION_BUILT_FROM) ], gaps: [ "Jobs could not be read" ]))

    service = resource("web")
    assert_equal "running", service.status
    assert_equal @row, service.integration_environment
    assert_equal [ [ "web", ResourceMap::RELATION_BUILT_FROM, "acme/app" ] ],
                 ResourceMap::Link.where(workspace: @workspace).map { |each| [ each.from_resource.external_id, each.relation, each.to_resource.external_id ] }
    assert_equal ResourceMap::ORIGIN_DECLARED, service.links_out.sole.origin
    assert_equal [ "Jobs could not be read" ], @row.reload.map_gaps
    assert @row.map_swept_at
  end

  test "what a connection no longer reports is marked removed, and comes back with its first sighting kept" do
    ResourceMap.record!(@row, snapshot(web), at: 2.days.ago)
    first_seen = resource("web").first_seen_at

    ResourceMap.record!(@row, snapshot)
    assert resource("web").removed_at

    ResourceMap.record!(@row, snapshot(web))
    assert_nil resource("web").removed_at
    assert_equal first_seen, resource("web").first_seen_at
  end

  test "a sweep replaces its own links and keeps a person's" do
    ResourceMap.record!(@row, snapshot(web, repository, links: [ link(web, repository, ResourceMap::RELATION_BUILT_FROM) ]))
    ResourceMap::Link.create!(workspace: @workspace, from_resource: resource("web"), to_resource: resource("acme/app"),
                              relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_PERSON, last_seen_at: Time.current)

    ResourceMap.record!(@row, snapshot(web, repository))

    assert_equal [ ResourceMap::ORIGIN_PERSON ], resource("web").links_out.map(&:origin)
  end

  test "a sweep records what changed: what appeared, a new running commit, a status that moved, and what is gone" do
    ResourceMap.record!(@row, snapshot(deployed("aaa", "running")), at: 1.hour.ago)
    ResourceMap.record!(@row, snapshot(deployed("bbb", "failed")))
    ResourceMap.record!(@row, snapshot)

    changes = resource("web").changes_seen.order(:happened_at, :kind).map { |change| [ change.kind, change.from_value, change.to_value ] }
    assert_equal [ [ ResourceMap::Change::KIND_APPEARED, nil, nil ], [ ResourceMap::Change::KIND_DEPLOYED, "aaa", "bbb" ],
                   [ ResourceMap::Change::KIND_STATUS_CHANGED, "running", "failed" ], [ ResourceMap::Change::KIND_REMOVED, nil, nil ] ].sort_by(&:first),
                 changes.sort_by(&:first)
  end

  test "what a provider reported is named for a person, in reading order, with the running commit shortened" do
    facts = ResourceMap.facts("deployed_commit" => "c4e4267d46e638ac", "plan" => "nf-compute-100-2", "production" => true, "appId" => "/team/p/web")

    assert_equal [ [ "Plan", "nf-compute-100-2" ], [ "Running commit", "c4e4267" ], [ "Production", "Yes" ] ], facts
  end

  test "a provider's status reads as healthy, busy, failing or unknown, and in words" do
    resource = ResourceMap::Resource.new(status: "in_progress")

    assert_equal ResourceMap::Resource::HEALTH_BUSY, resource.health
    assert_equal "In progress", resource.status_label
    assert_equal ResourceMap::Resource::HEALTH_OK, ResourceMap::Resource.new(status: "COMPLETED").health
    assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: "failed").health
    assert_equal ResourceMap::Resource::HEALTH_UNKNOWN, ResourceMap::Resource.new(status: "sleepy").health
  end

  test "a resource two connections report is one resource" do
    other = connection("northflank_two")
    ResourceMap.record!(@row, snapshot(repository))
    ResourceMap.record!(other, snapshot(repository))

    assert_equal 1, ResourceMap::Resource.where(workspace: @workspace, external_id: "acme/app").count
  end

  private

  def connection(slug)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: slug.humanize, slug: slug)
    integration.integration_environments.create!
  end

  def web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web", status: "running")

  def deployed(commit, status)
    ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web",
                           status: status, details: { "deployed_commit" => commit })
  end

  def repository = ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/app", name: "acme/app")

  def link(from, to, relation) = ResourceMap::FoundLink.new(from: from.key, to: to.key, relation: relation)

  def snapshot(*resources, links: [], gaps: []) = ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)

  def resource(external_id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: external_id)
end
