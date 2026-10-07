require "test_helper"

class ResourceMap::LogTemplateTest < ActiveSupport::TestCase
  TEMPLATE = ResourceMap::LogTemplate
  MINER = ResourceMap::LogMiner

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = @northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @logs = @northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = resource!(ResourceMap::KIND_SERVICE, "web")
  end

  test "a read keeps each pattern encrypted with its lines, counts the reads that saw it, and drops what a week has not seen" do
    TEMPLATE.record!(@row, @web, MINER.mine([ "user ada logged in", "user bob logged in", "ERROR db timeout after 30 ms" ]), at: 3.days.ago)
    TEMPLATE.record!(@row, @web, MINER.mine([ "user eve logged in" ]), at: 1.day.ago)

    kept = @web.log_templates.this_week.most_lines_first.to_a
    assert_equal [ [ "user <*> logged in", 1, 2 ], [ "ERROR db timeout after <NUM> ms", 1, 1 ] ], kept.map { |pattern| [ pattern.template, pattern.lines, pattern.samples ] }
    assert_equal "error", kept.last.level
    raw = TEMPLATE.connection.select_value("SELECT template FROM resource_map_log_templates WHERE id = #{TEMPLATE.connection.quote(kept.first.id)}")
    assert_not_includes raw, "logged in"

    TEMPLATE.record!(@row, @web, MINER.mine([ "user eve logged in" ]), at: Time.current + 5.days)
    assert_equal [ "user <*> logged in" ], @web.log_templates.reload.map(&:template)
  end

  test "only the patterns with the most lines are kept" do
    patterns = 3.times.map { |index| MINER::Pattern.new(template: "pattern #{index}", lines: index + 1, level: nil) }
    TEMPLATE.record!(@row, @web, patterns, keep: 2)
    assert_equal [ "pattern 2", "pattern 1" ], @web.log_templates.most_lines_first.map(&:template)
    assert_equal 200, TEMPLATE::KEPT
  end

  test "recent lines are set against the usual ones: what is new this week, and which errors are usual" do
    TEMPLATE.record!(@row, @web, MINER.mine([ "user ada logged in", "ERROR db timeout after 30 ms", "ERROR db timeout after 31 ms" ]), at: 1.day.ago)

    comparison = TEMPLATE.compare(@web, [ "user zed logged in", "ERROR db timeout after 90 ms", "ERROR disk full on /var/lib" ])

    assert_equal [ 3, 2 ], [ comparison.lines_read, comparison.usual ]
    assert_equal [ "ERROR disk full on /var/lib" ], comparison.new_patterns.map(&:template)
    assert_equal [ "ERROR db timeout after <NUM> ms" ], comparison.usual_errors.map { |_pattern, kept| kept.template }

    report = TEMPLATE.report(@web, comparison, from: "Northflank", minutes: 60)
    assert_match "Read 3 log lines of web from Northflank over the last 60 minutes. 2 usual patterns were seen in the last week.", report
    assert_match "Not seen in the last week, most lines first:\n- [error] ERROR disk full on /var/lib (1 line)", report
    assert_match "Error patterns that are usual, seen in the last week, so not the cause by themselves:\n- ERROR db timeout after <NUM> ms (1 line now, seen in 1 daily read)", report
  end

  test "the daily read covers app kinds that run a catalog entry, anything whose services had incidents, and the most depended on" do
    worker = resource!(ResourceMap::KIND_WORKER, "jobs")
    database = resource!(ResourceMap::KIND_DATABASE, "orders-db")
    lonely = resource!(ResourceMap::KIND_SERVICE, "lonely")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:platform_team), resource: worker)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: database)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: database, relation: ResourceMap::RELATION_USES,
                              origin: ResourceMap::ORIGIN_DECLARED, integration_environment: @row, last_seen_at: Time.current)

    scope = TEMPLATE.scope_of(@workspace)
    assert_includes scope, worker
    assert_includes scope, database, "the most depended on"

    IncidentFieldValue.create!(incident: incidents(:active_critical_ws1), incident_field_definition: incident_field_definitions(:affected_services_ws1),
                               catalog_entry: catalog_entries(:auth_service))
    assert_equal [ database, worker ], TEMPLATE.scope_of(@workspace).first(2), "a resource with incidents comes first"
    assert_not_includes TEMPLATE.scope_of(@workspace), lonely, "nothing depends on it"
  end

  test "a resource with no usual lines says why, worked out live" do
    assert_match "Link it to the catalog entry it runs", TEMPLATE.missing_reason(@web, @alice)

    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @web)
    assert_match "Not read yet", TEMPLATE.missing_reason(@web, @alice)

    @logs.update!(enabled: false)
    assert_match "Its logs cannot be read, so its usual lines are not known. Northflank would answer this with its search_logs tool, which is switched off",
                 TEMPLATE.missing_reason(@web, @alice)

    TEMPLATE.record!(@row, @web, MINER.mine([ "worker started" ]))
    assert_nil TEMPLATE.missing_reason(@web, @alice)
  end

  private

  def resource!(kind, id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: kind, external_id: id, name: id,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
