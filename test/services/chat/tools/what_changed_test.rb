require "test_helper"

class Chat::Tools::WhatChangedTest < ActiveSupport::TestCase
  History = Integrations::Capabilities::History

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @builds = northflank.tools.create!(name: "build_history", description: "Builds", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @logs = northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                         name: "web", integration_environment: @row, first_seen_at: 2.days.ago, last_seen_at: Time.current)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, from_value: "a" * 40, to_value: "b" * 40, happened_at: 1.hour.ago)
  end

  test "Halon holds what_changed with the map's tools, and it reads a resource's runs as run history beside what the map saw, each a step" do
    run = History::Run.new(id: "b46", number: "46", name: "build", status: History::SUCCEEDED, started_at: 20.minutes.ago, finished_at: 15.minutes.ago)
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @builds && arguments == { "resource" => "web-id", "limit" => History::LIMIT } }
                                .returns(Integrations::Capabilities::RunHistory.with_runs({ "content" => [ { "type" => "text", "text" => "1 build" } ] }, [ run ]))
    entry = catalog_entry(ResourceMap::Timeline::TOOL_NAME)
    assert_equal [ Chat::Tools::STATE_READY, Chat::Tools::Groups::MAP ], [ entry.state, entry.group ]

    answer = entry.tool.call("resource" => "web", "minutes" => 120)

    assert_match(/What changed for web from \S+ to \S+, newest first:\n- \S+ Run: web run #46 build succeeded, took 5 minutes, from Northflank\n- \S+ Deploy: web deployed bbbbbbb/, answer)
    assert_equal "northflank.build_history", @investigation.steps.find_by!(tool_name: "run_history").action_key
    listed = @investigation.steps.find_by!(tool_name: ResourceMap::Timeline::TOOL_NAME)
    assert_equal [ Ability::Action::MAP_READ, "What changed for web" ], [ listed.action_key, listed.label ]
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(ResourceMap::Timeline::TOOL_NAME, @workspace)
  end

  test "a window it cannot read is refused in words" do
    assert_match "start must be before end", catalog_entry(ResourceMap::Timeline::TOOL_NAME).tool.call("start" => 1.hour.from_now.iso8601)
  end

  test "logs whose failing lines name an outside provider's host carry that provider's status, read now as a web read step" do
    lines = [ "ERROR Net::ReadTimeout calling https://api.github.com/repos", "INFO ok" ].map do |text|
      Integrations::Telemetry::LogLine.new(at: Time.current, source: "web", text: text)
    end
    Integrations::NativeExecutor.expects(:call).returns(Integrations::Telemetry.result(Integrations::Telemetry.logs_text(lines, asked: "web"), link: nil))
    Integrations::Http.expects(:json).returns({ "status" => { "indicator" => "major", "description" => "Partial System Outage" }, "components" => [], "incidents" => [] })

    answer = catalog_entry("search_logs").tool.call("resource" => "web")

    assert_match "Failing lines here name api.github.com, which is GitHub's. Its status page, read now:", answer
    assert_match "GitHub status, from https://www.githubstatus.com, read at", answer
    assert_match "Partial System Outage.", answer
    step = @investigation.steps.find_by!(tool_name: Mcp::Tools::CHECK_STATUS_PAGE)
    assert_equal [ Ability::Action::WEB_READ, "Check GitHub's status page" ], [ step.action_key, step.label ]
  end

  test "with web search switched off the status page is named and not read" do
    @workspace.update!(web_search_enabled: false)
    lines = [ Integrations::Telemetry::LogLine.new(at: Time.current, source: "web", text: "ERROR connect ECONNREFUSED api.github.com:443") ]
    Integrations::NativeExecutor.expects(:call).returns(Integrations::Telemetry.result(Integrations::Telemetry.logs_text(lines, asked: "web"), link: nil))
    Integrations::StatusPages.expects(:read).never

    answer = catalog_entry("search_logs").tool.call("resource" => "web")

    assert_match "Failing lines here name api.github.com, which is GitHub's. Its status page is https://www.githubstatus.com, which Firefight cannot read here. " \
                 "Web search is switched off for this workspace.", answer
  end

  private

  def catalog_entry(name) = Chat::Tools.catalog(@investigation).find { |each| each.name == name }
end
