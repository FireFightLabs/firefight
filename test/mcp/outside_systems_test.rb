require "test_helper"

# what_changed, check_status_page and blind_spots as an outside agent calls them over MCP.
class Mcp::OutsideSystemsTest < ActiveSupport::TestCase
  History = Integrations::Capabilities::History

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @builds = northflank.tools.create!(name: "build_history", description: "Builds", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @logs = northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                         name: "web", integration_environment: @row, first_seen_at: 2.days.ago, last_seen_at: Time.current)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_STATUS_CHANGED, from_value: "running", to_value: "failed", happened_at: 1.hour.ago)
  end

  test "what_changed puts a resource's runs, read through run history as the provider's own call, beside what the map saw" do
    run = History::Run.new(id: "b46", number: "46", name: "build", status: History::FAILED, started_at: 10.minutes.ago, finished_at: 5.minutes.ago,
                           url: "https://app.northflank.com/builds/46")
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @builds && arguments == { "resource" => "web-id", "limit" => History::LIMIT } }
                                .returns(Integrations::Capabilities::RunHistory.with_runs({ "content" => [ { "type" => "text", "text" => "1 build" } ] }, [ run ]))

    response = Mcp::CapabilityToolFactory.what_changed({ workspace: @workspace, principal: @alice }, { resource: "web", minutes: 180 })

    text = response.content.sole[:text]
    assert_match(/- \S+ Run: web run #46 build failed, took 5 minutes, from Northflank https:\/\/app.northflank.com\/builds\/46\n- \S+ Status: web went from running to failed/, text)
    assert_equal %w[run status], response.structured_content[:changes].map { |entry| entry[:kind] }
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.build_history", source: AbilityGateway::SOURCE_MCP)
  end

  test "what_changed says which runs could not be read, and refuses what it cannot find in words" do
    Integrations::NativeExecutor.expects(:call).raises(Integrations::Error, "Northflank answered 500: down")

    text = Mcp::CapabilityToolFactory.what_changed({ workspace: @workspace, principal: @alice }, { resource: "web" }).content.sole[:text]

    assert_match "Not in this list:\n- The runs of web could not be read: Upstream tool failed: Northflank answered 500: down", text
    assert_match "Nothing on the resource map is called nope", Mcp::CapabilityToolFactory.what_changed({ workspace: @workspace, principal: @alice }, { resource: "nope" }).content.sole[:text]
    assert Mcp::CapabilityToolFactory.what_changed({ workspace: @workspace, principal: @alice }, { minutes: 99_999_999 }).error?
  end

  test "logs whose failing lines name an outside provider's host point at its status page" do
    lines = [ "ERROR Net::ReadTimeout calling https://api.stripe.com/v1/charges" ].map { |text| Integrations::Telemetry::LogLine.new(at: Time.current, source: "web", text: text) }
    Integrations::NativeExecutor.expects(:call).returns(Integrations::Telemetry.result(Integrations::Telemetry.logs_text(lines, asked: "web"), link: nil))

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert_equal "Failing lines here name api.stripe.com, which is Stripe's. check_status_page reads its status page, https://status.stripe.com.", response.content.last[:text]
  end

  test "check_status_page reads a provider's page by its name or by the host the errors name, as a web read" do
    Integrations::StatusPages.expects(:read).with(Upstream.find("stripe"))
                             .returns(Integrations::StatusPages::Reading.new(entry: Upstream.find("stripe"), state: Integrations::StatusPages::UNKNOWN,
                                                                             headline: "Read from the page", text: "All services are online.", read_at: Time.current))

    response = Mcp::Tools::CheckStatusPage.call(server_context: { workspace: @workspace, principal: @alice }, host: "api.stripe.com")

    assert_match "Stripe status, from https://status.stripe.com, read at", response.content.sole[:text]
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: Ability::Action::WEB_READ, source: AbilityGateway::SOURCE_MCP)
    assert_match "Firefight knows no status page for nowhere.example", Mcp::Tools::CheckStatusPage.perform(workspace: @workspace, args: { host: "nowhere.example" }).content.sole[:text]
  end

  test "check_status_page reads nothing where the workspace switched web search off, and gives the page to open" do
    @workspace.update!(web_search_enabled: false)
    Integrations::StatusPages.expects(:read).never

    response = Mcp::Tools::CheckStatusPage.perform(workspace: @workspace, args: { provider: "GitHub" })

    assert response.error?
    assert_equal "Web search is switched off for this workspace. GitHub's status page is https://www.githubstatus.com, which a person can open.", response.content.sole[:text]
  end

  test "blind_spots names a system the apps use that nothing connects, and says when there is none" do
    assert_equal Upstream::BlindSpots::NONE, Mcp::Tools::BlindSpots.perform_with_principal(workspace: @workspace, principal: @alice, args: {}).structured_content[:note]
    ResourceMap::Use.create!(workspace: @workspace, resource: @web, integration_environment: @row, variable: "CLERK_SECRET_KEY", last_seen_at: Time.current)

    spots = Mcp::Tools::BlindSpots.perform_with_principal(workspace: @workspace, principal: @alice, args: { category: "Sign-in" }).structured_content[:blind_spots]

    assert_equal [ "Clerk" ], spots.map { |spot| spot[:system] }
    assert_equal [ "web's setting CLERK_SECRET_KEY is named for it" ], spots.sole[:evidence]
  end
end
