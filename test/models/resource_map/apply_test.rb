require "test_helper"

class ResourceMap::ApplyTest < ActiveSupport::TestCase
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = connect_live!(@workspace)
    @web = LiveTestPack.found(ResourceMap::KIND_SERVICE, "web")
    @worker = LiveTestPack.found(ResourceMap::KIND_SERVICE, "worker")
    @db = LiveTestPack.found(ResourceMap::KIND_DATABASE, "main")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @web, @worker, @db ], links: [ ResourceMap::FoundLink.new(from: @web.key, to: @db.key, relation: ResourceMap::RELATION_USES) ]))
  end

  def scope_of(found) = ResourceMap::Scope.new(account: found.account, kind: found.kind, external_id: found.external_id)

  def resource(name) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: "livetest", external_id: name)

  test "a re-read writes only what it read, and a change is recorded at the time the provider says it happened" do
    happened = 3.minutes.ago.change(usec: 0)
    partial = ResourceMap::Snapshot.new(resources: [ @web.with(status: "failed") ])

    ResourceMap.apply!(@row, partial, scope: scope_of(@web), at: happened)

    assert_equal "failed", resource("web").status
    change = resource("web").changes_seen.find_by!(kind: ResourceMap::Change::KIND_STATUS_CHANGED)
    assert_equal happened, change.happened_at
    assert_nil resource("worker").removed_at, "a resource the re-read did not name is left alone"
    assert_nil resource("main").removed_at
  end

  test "nothing is removed for being absent from a re-read, only for the provider answering not found" do
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: []), scope: scope_of(@worker), at: Time.current)
    assert_nil resource("worker").removed_at

    gone_at = 1.minute.ago.change(usec: 0)
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [], gone: [ @worker.key ]), scope: scope_of(@worker), at: gone_at)

    assert_equal gone_at, resource("worker").removed_at
    assert_equal gone_at, resource("worker").changes_seen.find_by!(kind: ResourceMap::Change::KIND_REMOVED).happened_at
  end

  test "a not found outside the scope asked is ignored, and another connection's sighting keeps a resource" do
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [], gone: [ @db.key ]), scope: scope_of(@worker), at: Time.current)
    assert_nil resource("main").removed_at

    other = connect_live!(@workspace, name: "Live test two", slug: "livetest_two")
    ResourceMap.record!(other, ResourceMap::Snapshot.new(resources: [ @db ]))
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [], gone: [ @db.key ]), scope: scope_of(@db), at: Time.current)

    assert_nil resource("main").removed_at
    assert_equal [ other.id ], resource("main").sightings.keys
  end

  test "declared links are replaced only for the resources read again, and only by a complete read" do
    cache = LiveTestPack.found(ResourceMap::KIND_DATABASE, "cache")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @web, @worker, @db, cache ], links: [
      ResourceMap::FoundLink.new(from: @web.key, to: @db.key, relation: ResourceMap::RELATION_USES),
      ResourceMap::FoundLink.new(from: @worker.key, to: @db.key, relation: ResourceMap::RELATION_USES)
    ]))
    gap = ResourceMap::Gap.new(text: "Links could not be read.", kinds: [ ResourceMap::KIND_DATABASE ])

    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [ @web ], gaps: [ gap ]), scope: scope_of(@web), at: Time.current)
    assert ResourceMap::Link.exists?(from_resource_id: resource("web").id, to_resource_id: resource("main").id), "an incomplete read keeps links"

    moved = ResourceMap::Snapshot.new(resources: [ @web ], links: [ ResourceMap::FoundLink.new(from: @web.key, to: cache.key, relation: ResourceMap::RELATION_USES) ])
    ResourceMap.apply!(@row, moved, scope: scope_of(@web), at: Time.current)

    assert_equal [ resource("cache").id ], ResourceMap::Link.where(from_resource_id: resource("web").id).pluck(:to_resource_id)
    assert ResourceMap::Link.exists?(from_resource_id: resource("worker").id, to_resource_id: resource("main").id), "a link from a resource not read again stays"
  end

  test "a resource a sweep wrote after the re-read began keeps what the sweep wrote" do
    read_at = 1.minute.ago
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @web.with(status: "healthy"), @worker, @db ]))

    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [ @web.with(status: "failed") ], gone: [ @worker.key ]), scope: ResourceMap::Scope.new(account: "acme"), at: 2.minutes.ago, read_at: read_at)

    assert_equal "healthy", resource("web").status
    assert_nil resource("worker").removed_at
  end

  test "a resource the provider reports again after it was confirmed gone comes back" do
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [], gone: [ @worker.key ]), scope: scope_of(@worker), at: 2.minutes.ago)
    ResourceMap.apply!(@row, ResourceMap::Snapshot.new(resources: [ @worker ]), scope: scope_of(@worker), at: 1.minute.ago)

    assert_nil resource("worker").removed_at
    assert resource("worker").changes_seen.exists?(kind: ResourceMap::Change::KIND_APPEARED)
  end
end
