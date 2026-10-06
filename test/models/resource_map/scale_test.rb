require "test_helper"

# A workspace holding 100,000 resources among other workspaces' resources, read through its indexes. A plan that scans
# either table in full would read every workspace's rows, so each query's plan is checked rather than its time, which
# varies by machine. Rows are written by the database itself, since building them in Ruby takes far longer than the test.
class ResourceMap::ScaleTest < ActiveSupport::TestCase
  RESOURCES = 100_000
  OTHERS = 150_000
  CHAIN = 10
  FULL_SCANS = /Seq Scan on resource_map_(resources|links)\b/

  setup do
    @workspace = workspaces(:slack_workspace_one)
    fill(@workspace, RESOURCES, linked: true)
    fill(workspaces(:slack_workspace_two), OTHERS)
    fill(workspaces(:slack_workspace_expired), OTHERS)
    connection.execute("ANALYZE resource_map_resources")
    connection.execute("ANALYZE resource_map_links")
  end

  test "every filter, a later page, the capped count and the walk along links read through indexes" do
    first = ResourceMap::Query.new(@workspace).page(limit: 50)
    assert_equal [ ResourceMap::Query::COUNT_CAP, true, "10,000+" ], [ first.total, first.capped, first.total_label ]

    {
      "first page" => {}, "provider and account" => { provider: "aws", account: "account-2" }, "kind" => { kind: ResourceMap::KIND_DATABASE },
      "status" => { status: "failed" }, "health" => { health: ResourceMap::Resource::HEALTH_FAILING }, "tag" => { tag: "team=payments" },
      "tag named alone" => { tag: "team" }, "field" => { fields: { ResourceMap::TAGS => { "team" => "payments" } } }, "name prefix" => { name_prefix: "resource-0999" }
    }.each do |label, filters|
      query = ResourceMap::Query.new(@workspace, **filters)
      assert_indexed query.listing(cursor: first.next_cursor, limit: 51), label
      # The count stops at the cap, so a scan that stops there costs little, and the planner rightly takes one for a
      # workspace that is a large share of the table. A filter has to narrow it through an index.
      counting = explain(query.scope.limit(ResourceMap::Query::COUNT_CAP + 1).select(:id).to_sql)
      assert_match(/\ALimit/, counting, "#{label} count")
      assert_no_match FULL_SCANS, counting, "#{label} count" if filters.any?
    end

    root = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "resource-0")
    graph = ResourceMap::Graph.new(root)

    assert_equal CHAIN - 1, graph.total
    assert_equal CHAIN - 1, graph.nodes.last.hop
    assert_no_match FULL_SCANS, explain(graph.reached_sql)
    assert_no_match FULL_SCANS, explain(ResourceMap::Graph.new(root, kinds: [ ResourceMap::KIND_SERVICE ]).reached_sql)
    last = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "resource-#{CHAIN - 1}")
    assert_no_match FULL_SCANS, explain(ResourceMap::Graph.new(last, direction: ResourceMap::Graph::DEPENDS_ON).reached_sql)
    assert_equal graph.resources.pluck(:id).sort, ResourceMap::BlastRadius.new(root).dependent_ids.sort
  end

  test "the map tools answer on the large map, and get_resource_map gives its numbers rather than reading every resource" do
    admin = workspace_memberships(:alice_workspace_one)
    timings = {
      Mcp::Tools::GetResourceMap => {}, Mcp::Tools::FindResources => { provider: [ "aws" ], name_starts_with: "resource-01" },
      Mcp::Tools::GetResource => { resource: "resource-5" }, Mcp::Tools::GetResourceLinks => { resource: "resource-5" },
      Mcp::Tools::GetResourceNeighbours => { resource: "resource-5" },
      Mcp::Tools::TraverseResourceMap => { resource: "resource-0", direction: ResourceMap::Graph::DEPENDENTS, hops: 6 },
      Mcp::Tools::BlastRadius => { resource: "resource-0" }, Mcp::Tools::ResourceMapStats => { group_by: ResourceMap::Stats::BY_ACCOUNT }
    }.to_h do |tool, args|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answer = tool.perform_with_principal(workspace: @workspace, principal: admin, args: args).structured_content
      assert_nil answer[:error], tool.name
      [ tool, [ answer, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started ] ]
    end

    overview = timings[Mcp::Tools::GetResourceMap].first
    assert_equal RESOURCES, overview[:resources]
    assert_nil overview[:accounts]
    assert_equal CHAIN - 1, timings[Mcp::Tools::BlastRadius].first[:dependents]
    assert_equal "10,000+", Mcp::Tools::FindResources.perform_with_principal(workspace: @workspace, principal: admin, args: {}).structured_content[:total]
    # Generous, since machines differ. A tool that read every resource row into Ruby would take far longer.
    timings.each { |tool, (_, seconds)| assert_operator seconds, :<, 10, tool.name }
  end

  test "the matchers read only the pairs that share a word or an address, so a sweep on the large map stays quick" do
    row = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws_scale").integration_environments.create!
    # Each database is named for its own project, and three services for each of the first thousand projects share it.
    connection.execute(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, { workspace: @workspace.id } ]))
      UPDATE resource_map_resources SET name = CASE WHEN kind = 'database' THEN 'p' || substring(external_id FROM 10) || 'x-prod'
                                                    WHEN substring(external_id FROM 10)::int < 4000 THEN 'p' || (substring(external_id FROM 10)::int % 1000) || 'x-web'
                                                    ELSE name END
      WHERE workspace_id = :workspace
    SQL
    # Every service has a setting, and the three services of each of the first thousand projects name the address its database reports.
    connection.execute(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, { workspace: @workspace.id, row: row.id } ]))
      INSERT INTO resource_map_uses (workspace_id, resource_id, integration_environment_id, variable, fingerprint, port, last_seen_at, created_at, updated_at)
      SELECT :workspace, id, :row, 'DATABASE_URL',
             md5(CASE WHEN substring(external_id FROM 10)::int < 4000 THEN 'address' || (substring(external_id FROM 10)::int % 1000)
                      ELSE 'elsewhere' || external_id END), 5432, now(), now(), now()
      FROM resource_map_resources WHERE workspace_id = :workspace AND kind = 'service'
    SQL
    connection.execute(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, { workspace: @workspace.id, row: row.id } ]))
      INSERT INTO resource_map_endpoints (workspace_id, resource_id, integration_environment_id, fingerprint, port, last_seen_at, created_at, updated_at)
      SELECT :workspace, id, :row, md5('address' || substring(external_id FROM 10)), 5432, now(), now(), now()
      FROM resource_map_resources WHERE workspace_id = :workspace AND kind = 'database'
    SQL
    connection.execute("ANALYZE resource_map_uses")
    connection.execute("ANALYZE resource_map_endpoints")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ResourceMap::Matcher.new(@workspace).run!
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    links = ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_USES, origin: [ ResourceMap::ORIGIN_MATCHED, ResourceMap::ORIGIN_INFERRED ])
    assert_equal 3000, links.where(origin: ResourceMap::ORIGIN_MATCHED).count
    assert_equal 0, links.where(origin: ResourceMap::ORIGIN_INFERRED).count, "a pair matched exactly is not suggested as well"
    # Generous, since machines differ. Comparing every service with every database in Ruby would take far longer.
    assert_operator seconds, :<, 60
  end

  private

  def assert_indexed(relation, label) = assert_no_match FULL_SCANS, explain(relation.to_sql), label

  def explain(sql) = connection.select_values("EXPLAIN #{sql}").join("\n")

  def connection = ResourceMap::Resource.connection

  # Resources named resource-000000 onwards, the first thousand databases and the rest services, across two providers,
  # a hundred accounts and three statuses, one in a hundred tagged. Linked, each one uses the one before it in chains
  # of ten. Other workspaces' links are left out, since writing them is most of the test's time and no plan reads them.
  def fill(workspace, count, linked: false)
    connection.execute(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, { workspace: workspace.id, last: count - 1 } ]))
      INSERT INTO resource_map_resources (workspace_id, provider, account, kind, external_id, name, status, details, first_seen_at, last_seen_at, created_at, updated_at)
      SELECT :workspace, CASE WHEN i % 2 = 0 THEN 'aws' ELSE 'google_cloud' END, 'account-' || (i % 100),
             CASE WHEN i < 1000 THEN 'database' ELSE 'service' END, 'resource-' || i, 'resource-' || lpad(i::text, 6, '0'),
             (ARRAY['running', 'failed', 'pending'])[i % 3 + 1],
             CASE WHEN i % 100 = 0 THEN '{"tags": {"team": "payments"}}'::jsonb ELSE '{}'::jsonb END, now(), now(), now(), now()
      FROM generate_series(0, :last) AS i
    SQL
    return unless linked

    connection.execute(ResourceMap::Resource.sanitize_sql_array([ <<~SQL.squish, { workspace: workspace.id } ]))
      WITH numbered AS (
        SELECT id, substring(external_id FROM 10)::int AS i FROM resource_map_resources WHERE workspace_id = :workspace
      )
      INSERT INTO resource_map_links (workspace_id, from_resource_id, to_resource_id, relation, origin, last_seen_at, created_at, updated_at)
      SELECT :workspace, later.id, earlier.id, 'uses', 'declared', now(), now(), now()
      FROM numbered later JOIN numbered earlier ON earlier.i = later.i - 1
      WHERE later.i % #{CHAIN} <> 0
    SQL
  end
end
