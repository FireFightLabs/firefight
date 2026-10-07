require "test_helper"

class SearchDocument::SearchTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank search", slug: "northflank_search")
    @row = integration.integration_environments.create!(environment: catalog_entries(:production_env))
  end

  test "an exact id comes before a resource that only holds the word, and a fragment or a misspelling still finds a name" do
    record(found("svc-123", name: "checkout"), found("svc-123-proxy"), found("billing", details: { "upstream" => "svc-123" }),
           found("ledger-db", kind: ResourceMap::KIND_DATABASE))

    assert_equal [ "checkout", "svc-123-proxy", "billing" ], titles("svc-123")
    assert_equal "Exactly its provider id.", search("svc-123").results.first.why
    assert_equal "Matches its details.", search("svc-123").results.last.why
    assert_equal [ "ledger-db" ], titles("ledg")
    assert_equal [ "ledger-db" ], titles("ledgr")
    assert_equal "Close to its name or id.", search("ledgr").results.sole.why
  end

  test "ids and names are matched as written, never cut to a stem" do
    record(found("jobs-runner"), found("job"), found("runner-ops"))

    assert_equal "jobs-runner", titles("jobs").first
    assert_equal "Close to its name or id.", why_for("jobs", "job")
    assert_equal "jobs-runner", titles("jobs-runner").first
    assert_empty titles("ran")
  end

  test "a resource is found by its tags, the services it runs and the team that owns them" do
    record(found("web", details: { ResourceMap::TAGS => { "team" => "ledger" } }))
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: resource("web"))
    index_everything

    assert_includes titles("team=ledger"), "web"
    assert_equal "Matches a team that owns it.", why_for("platform", "web")
    assert_equal "Matches a catalog entry it runs.", why_for("auth", "web")
  end

  test "catalog entries, their owners and confirmed memories are found with resources, ranked together" do
    record(found("auth-api"))
    Chat::Memory.create!(workspace: @workspace, text: "Auth tokens are signed by the auth-api service", state: Chat::Memory::STATE_CONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: "Auth retries twice before failing", state: Chat::Memory::STATE_UNCONFIRMED)

    results = search("auth").results

    assert_equal [ "Auth Service", "auth-api", "Auth tokens are signed by the auth-api service" ].sort, results.map(&:title).sort
    assert_equal SearchDocument::Search::TYPES.sort, results.map(&:type).uniq.sort
    memory = results.find { |result| result.type == SearchDocument::Search::TYPE_MEMORY }
    assert_equal "A confirmed memory holds these words.", memory.why
    assert_equal "/app/memory?memory=#{memory.id}", memory.path
    assert_equal "/app/catalogue/service?entry=#{catalog_entries(:auth_service).id}", results.find { |result| result.type == SearchDocument::Search::TYPE_CATALOG_ENTRY }.path
    assert_equal "/app/map?resource=#{resource('auth-api').id}&view=focus", results.find { |result| result.type == SearchDocument::Search::TYPE_RESOURCE }.path
  end

  test "memories are left out when the agent is not available, since the Memory page would not open" do
    Chat::Memory.create!(workspace: @workspace, text: "Ledger writes go through the primary", state: Chat::Memory::STATE_CONFIRMED)
    Investigation.stubs(:available_for?).returns(false)

    page = search("ledger", types: [ SearchDocument::Search::TYPE_MEMORY ])

    assert_empty page.results
    assert_equal [ SearchDocument::Search::TYPE_MEMORY ], page.left_out
  end

  test "a reader narrowed to Production finds nothing from Development and no memory about it" do
    build_two_environment_map(@workspace)
    Chat::Memory.create!(workspace: @workspace, subject: map_resource(@workspace, "secret-db"), text: "secret-db holds the vault keys",
                         state: Chat::Memory::STATE_CONFIRMED)
    index_everything
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    assert_equal [ "orders-db" ], titles("db", principal: @member)
    hidden = search("secret vault dev-worker shop.example.com", principal: @member).results
    assert_empty hidden
    assert_includes titles("secret", principal: @admin), "secret-db"
  end

  test "each type is searched only when the caller may read it, and the rest are named as left out" do
    record(found("auth-api"))
    key = api_keys(:read_only_key)
    limit_map_to(@workspace, key, catalog_entries(:production_env))

    page = search("auth", principal: key)

    assert_equal [ "auth-api" ], page.results.map(&:title)
    assert_equal [ SearchDocument::Search::TYPE_CATALOG_ENTRY, SearchDocument::Search::TYPE_MEMORY ], page.left_out

    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { action: Ability::Action.system!("#{Ability::Action::RESOURCE_CATALOG}.#{Ability::Action::ACTION_READ}") })
    assert_includes search("auth", principal: key).results.map(&:title), "Auth Service"
  end

  test "a catalog entry is found by what it is for, only when the words found nothing better and the search needs it" do
    vector = Array.new(SearchEmbedding::DIMENSIONS) { |index| index.zero? ? 1.0 : 0.0 }
    SearchEmbedding.create!(workspace: @workspace, embeddable: catalog_entries(:auth_service), vector: vector, content_digest: "x", model: FirefightAi.embedding_model)
    asked = 0
    meaning = -> { asked += 1 and vector }

    results = search("people cannot sign in", meaning: meaning).results

    assert_equal [ "Auth Service" ], results.map(&:title)
    assert_equal "What it is for reads like the search.", results.sole.why
    search("ab", meaning: meaning)
    search("people cannot sign in", meaning: meaning, types: [ SearchDocument::Search::TYPE_RESOURCE ])
    assert_equal 1, asked
  end

  test "a map filter narrows the search to resources unless types say otherwise" do
    record(found("auth-api"), found("auth-db", kind: ResourceMap::KIND_DATABASE))

    assert_equal [ "auth-db" ], titles("auth", filters: { kind: [ ResourceMap::KIND_DATABASE ] })
    both = search("auth", filters: { kind: [ ResourceMap::KIND_DATABASE ] }, types: SearchDocument::Search::TYPES).results.map(&:title)
    assert_includes both, "Auth Service"
    assert_not_includes both, "auth-api"
  end

  test "pages follow a cursor tied to the search it came from" do
    record(*%w[queue-a queue-b queue-c].map { |name| found(name) })

    first = search("queue", limit: 2)
    second = search("queue", limit: 2, cursor: first.next_cursor)

    assert_equal 3, (first.results + second.results).map(&:title).uniq.size
    assert_nil second.next_cursor
    assert_raises(SearchDocument::Search::InvalidCursor) { search("other", cursor: first.next_cursor) }
    assert_raises(SearchDocument::Search::InvalidCursor) { search("queue", cursor: "garbage") }
  end

  test "a removed resource is not found" do
    record(found("old-api"))
    resource("old-api").update!(removed_at: Time.current)

    assert_empty titles("old-api")
  end

  private

  def found(id, name: id, kind: ResourceMap::KIND_SERVICE, details: {})
    ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: id, name: name, status: "running", details: details)
  end

  def record(*resources)
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: resources))
    index_everything
  end

  def index_everything
    SearchDocument.index!(ResourceMap::Resource, ResourceMap::Resource.where(workspace: @workspace).pluck(:id))
    SearchDocument.index!(CatalogEntry, @workspace.catalog_entries.pluck(:id))
  end

  def resource(external_id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: external_id)

  def search(query, principal: @admin, **options) = SearchDocument.search(@workspace, query, principal: principal, **options)

  def titles(query, **options) = search(query, **options).results.map(&:title)

  def why_for(query, title) = search(query).results.find { |result| result.title == title }.why
end
