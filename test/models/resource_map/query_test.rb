require "test_helper"

class ResourceMap::QueryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    @production = integration.integration_environments.create!(environment: catalog_entries(:production_env))
    @development = integration.integration_environments.create!(environment: catalog_entries(:development_env))
  end

  test "each filter narrows to what it names" do
    web = make("web", provider: "aws", account: "111", kind: ResourceMap::KIND_SERVICE, status: "running",
                      details: { "engine" => "none", ResourceMap::TAGS => { "team" => "payments", "pci" => nil } })
    orders = make("orders", provider: "aws", account: "222", kind: ResourceMap::KIND_DATABASE, status: "FAILED", row: @development,
                            details: { "engine" => "postgres 16", ResourceMap::TAGS => { "team" => "search" } })
    repo = make("acme/web", provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, status: nil, row: nil)

    assert_equal [ repo ], found(provider: "github")
    assert_equal [ orders, web ], found(provider: %w[aws])
    assert_equal [ orders ], found(kind: ResourceMap::KIND_DATABASE)
    assert_equal [ web ], found(account: "111")
    assert_equal [ orders ], found(environment: "development")
    assert_equal [ web ], found(environment: "Production")
    assert_equal [ orders ], found(status: "failed")
    assert_equal [ web ], found(health: ResourceMap::Resource::HEALTH_OK)
    assert_equal [ orders ], found(health: ResourceMap::Resource::HEALTH_FAILING)
    assert_equal [ repo ], found(health: ResourceMap::Resource::HEALTH_UNKNOWN)
    assert_equal [ repo, web ], found(health: [ ResourceMap::Resource::HEALTH_OK, ResourceMap::Resource::HEALTH_UNKNOWN ])
    assert_equal [ web ], found(tag: "team=payments")
    assert_equal [ web ], found(tag: "pci")
    assert_equal [ orders, web ], found(tag: "team")
    assert_equal [ orders ], found(tag: { "team" => "search" })
    assert_empty found(tag: "team=nobody")
    assert_equal [ orders ], found(fields: { engine: "postgres 16" })
    assert_equal [ orders ], found(name_prefix: "OR")
    assert_empty found(name_prefix: "%")
  end

  test "a team owns what is linked to it and to the services that name it as their owner, and catalog_entry finds its own" do
    web, api, other = make("web"), make("api"), make("other")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: web)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:platform_team), resource: api)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:production_env), resource: other)

    assert_equal [ api, web ], found(owner: catalog_entries(:platform_team))
    assert_equal [ web ], found(catalog_entry: catalog_entries(:auth_service).id)
    assert_empty found(owner: catalog_entries(:auth_service)), "only a team owns"
  end

  test "removed resources are left out unless asked for, and changed_since finds what changed" do
    kept = make("kept")
    gone = make("gone", removed_at: 1.hour.ago)
    kept.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 10.minutes.ago)
    gone.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_REMOVED, happened_at: 2.days.ago)

    assert_equal [ kept ], found
    assert_equal [ gone, kept ], found(include_removed: true)
    assert_equal [ kept ], found(changed_since: 1.hour.ago, include_removed: true)
  end

  test "within keeps the query, and the dependents it counts, to the resources a reader may see" do
    web, api = make("web"), make("api")
    link(api, web)
    visible = ResourceMap::Resource.where(name: "web")

    assert_equal [ web ], ResourceMap::Query.new(@workspace, within: visible).scope.to_a
    assert_equal [ 0 ], ResourceMap::Query.new(@workspace, within: visible, sort: ResourceMap::Query::SORT_DEPENDENTS).page.resources.map(&:dependents_count)
    assert_equal 1, ResourceMap::Query.new(@workspace, sort: ResourceMap::Query::SORT_DEPENDENTS).page.resources.first.dependents_count
  end

  test "pages in name order follow each other with nothing repeated or skipped, even when names are added between pages" do
    names = %w[delta Alpha charlie bravo echo foxtrot golf]
    names.each { |name| make(name) }
    query = ResourceMap::Query.new(@workspace)

    first = query.page(limit: 3)
    make("aardvark")
    make("zulu")
    second = query.page(cursor: first.next_cursor, limit: 3)
    third = query.page(cursor: second.next_cursor, limit: 3)

    assert_equal %w[Alpha bravo charlie], first.resources.map(&:name)
    assert_equal %w[delta echo foxtrot], second.resources.map(&:name)
    assert_equal %w[golf zulu], third.resources.map(&:name)
    assert_nil third.next_cursor
    assert_equal [ 7, false, "7" ], [ first.total, first.capped, first.total_label ]
  end

  test "pages by dependents put the most depended on first and break ties by id" do
    hub, leaf, *callers = %w[hub leaf a b c].map { |name| make(name) }
    callers.each { |caller| link(caller, hub) }
    link(callers.first, leaf)
    link(callers.second, leaf, origin: ResourceMap::ORIGIN_SUGGESTED)
    query = ResourceMap::Query.new(@workspace, sort: ResourceMap::Query::SORT_DEPENDENTS)

    pages = [ query.page(limit: 2) ]
    pages << query.page(cursor: pages.last.next_cursor, limit: 2) while pages.last.next_cursor

    ordered = pages.flat_map(&:resources)
    assert_equal [ hub, leaf ], ordered.first(2)
    assert_equal [ 3, 1 ], ordered.first(2).map(&:dependents_count), "an unconfirmed suggestion is not a dependent"
    assert_equal callers.sort_by(&:id), ordered.last(3)
    assert_equal 5, ordered.uniq.size
  end

  test "a cursor from another sort or not from a page is refused" do
    make("web")
    make("api")
    cursor = ResourceMap::Query.new(@workspace).page(limit: 1).next_cursor

    assert_raises(ResourceMap::Query::InvalidCursor) { ResourceMap::Query.new(@workspace, sort: ResourceMap::Query::SORT_DEPENDENTS).page(cursor: cursor) }
    assert_raises(ResourceMap::Query::InvalidCursor) { ResourceMap::Query.new(@workspace).page(cursor: "nonsense") }
  end

  private

  def make(name, provider: "aws", account: "111", kind: ResourceMap::KIND_SERVICE, status: "running", row: @production, details: {}, removed_at: nil)
    ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: account, kind: kind, external_id: name, name: name, status: status,
                                  integration_environment: row, details: details, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago, removed_at: removed_at)
  end

  def link(from, to, origin: ResourceMap::ORIGIN_DECLARED)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: ResourceMap::RELATION_USES, origin: origin, last_seen_at: Time.current)
  end

  def found(**filters) = ResourceMap::Query.new(@workspace, **filters).scope.order(:name).to_a
end
