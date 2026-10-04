require "test_helper"

class Integrations::Capabilities::SentryTest < ActiveSupport::TestCase
  # search_issues as a connection held to an organization lists it, without organizationSlug, which the server fills in.
  ISSUES_SCHEMA = { "type" => "object", "properties" => { "query" => {}, "sort" => {}, "projectSlugOrId" => {}, "limit" => {}, "period" => {} } }.freeze
  EXECUTE_SCHEMA = { "type" => "object", "properties" => { "name" => { "type" => "string" }, "arguments" => { "type" => "object" } }, "required" => [ "name" ] }.freeze
  RELEASES = {
    "releases" => [
      { "version" => "2.4.1", "dateCreated" => "2026-09-01T10:00:00.000Z", "dateReleased" => "2026-09-01T10:05:00.000Z",
        "firstEvent" => "2026-09-01T10:06:00.000Z", "lastEvent" => "2026-09-01T11:00:00.000Z", "newIssues" => 3, "projects" => [ "web" ],
        "lastCommit" => { "id" => "a1b2c3d4e5f6a7b8", "message" => "Cache carts per session\n\nLonger body", "author" => "Ana", "dateCreated" => "2026-09-01T09:00:00.000Z" },
        "lastDeploy" => { "id" => "77", "environment" => "production", "dateStarted" => "2026-09-01T10:02:00.000Z", "dateFinished" => "2026-09-01T10:04:00.000Z" } },
      { "version" => "2.4.0", "dateCreated" => "2026-08-30T10:00:00.000Z", "dateReleased" => nil, "firstEvent" => nil, "lastEvent" => nil,
        "newIssues" => 0, "projects" => [ "web" ], "lastCommit" => nil, "lastDeploy" => nil }
    ],
    "hasMore" => false
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    northflank.tools.create!(name: "list_deployments", description: "Deployments", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", slug: "sentry",
                                              settings: { "server_url" => "https://mcp.sentry.dev/mcp/acme" })
    @sentry_row = @sentry.integration_environments.create!
    @issues = @sentry.tools.create!(name: "search_issues", description: "Issues", read_only: true, enabled: true, params_schema: ISSUES_SCHEMA)
    @execute = @sentry.tools.create!(name: "execute_sentry_tool", description: "Run a catalog tool", read_only: false, enabled: true, params_schema: EXECUTE_SCHEMA)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Sentry answers errors for a service Northflank runs, by the project of the same name, last seen first in the range" do
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "text" => "Timeout \"cart\"", "minutes" => 30, "limit" => 500)

    assert_equal [ @sentry_row, "search_issues" ], [ errors.environment_row, errors.tool.name ]
    assert_equal({ "query" => "lastSeen:-30m message:\"Timeout cart\"", "sort" => "date", "period" => "24h", "projectSlugOrId" => "web", "limit" => 100 },
                 errors.arguments)
    assert_nil errors.fallback
  end

  test "a range with a start is sent as a comparison on when the issue was last seen, in the window that covers it" do
    travel_to Time.utc(2026, 9, 10, 12) do
      errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "start" => "2026-09-08T10:00:00Z", "end" => "2026-09-08T11:00:00Z")

      assert_equal "lastSeen:>=2026-09-08T10:00:00Z lastSeen:<=2026-09-08T11:00:00Z", errors.arguments["query"]
      assert_equal "7d", errors.arguments["period"]
      assert_match "last 90 days", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web", "start" => "2026-05-01T10:00:00Z", "end" => "2026-05-01T11:00:00Z")
    end
  end

  test "the platform answers deploys by default, and Sentry answers them through find_releases when it is named" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web").environment_row

    releases = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web", "connection" => "sentry")
    assert_equal [ @sentry_row, "execute_sentry_tool" ], [ releases.environment_row, releases.tool.name ]
    assert_equal({ "name" => "find_releases", "arguments" => { "projectSlug" => "web" } }, releases.arguments)
  end

  test "the releases are read into lines a person can follow, newest first, and an empty list is no answer" do
    releases = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web", "connection" => "sentry", "limit" => 1)
    text = releases.present_result({ "content" => [ { "type" => "text", "text" => RELEASES.to_json } ], "structuredContent" => RELEASES })["content"].first["text"]

    assert_match "Latest 1 releases of web in Sentry, newest first. Older releases were not listed.", text
    assert_match "release 2.4.1, created 2026-09-01T10:00:00.000Z, released 2026-09-01T10:05:00.000Z, last deployed to production at " \
                 "2026-09-01T10:04:00.000Z, commit a1b2c3d4e5f6 by Ana \"Cache carts per session\", 3 new issues", text
    assert_match "get_release_details", text
    assert_no_match "2.4.0", text

    from_text = releases.present_result({ "content" => [ { "type" => "text", "text" => RELEASES.to_json } ] })["content"].first["text"]
    assert_match "release 2.4.1", from_text

    empty = releases.present_result({ "content" => [ { "type" => "text", "text" => { "releases" => [], "hasMore" => false }.to_json } ] })
    assert_match "no releases for web", empty["content"].first["text"]
    assert_not Integrations::Capabilities.definitive?(empty)

    error = { "isError" => true, "content" => [ { "type" => "text", "text" => "Project not found" } ] }
    assert_equal error, releases.present_result(error)
  end

  test "a connection held to one project answers only for it and leaves the project to the server" do
    @sentry.update!(settings: { "server_url" => "https://mcp.sentry.dev/mcp/acme/web" })
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web")

    assert_not errors.arguments.key?("projectSlugOrId")
    assert_equal({ "name" => "find_releases", "arguments" => {} }, resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web", "connection" => "sentry").arguments)

    @sentry.update!(settings: { "server_url" => "https://mcp.sentry.dev/mcp/acme/checkout" })
    assert_match "only reads the checkout project", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web")
  end

  test "the connect form asks the organization and an optional project, and builds the address Sentry documents from them" do
    entry = IntegrationProvider.find("sentry")

    assert_equal "https://mcp.sentry.dev/mcp/acme/web", entry.server_url_for(nil, "organization" => "acme", "project" => "web")
    assert_equal "https://mcp.sentry.dev/mcp/acme", entry.server_url_for(nil, "organization" => "acme", "project" => "")
    assert_equal "Organization is required.", entry.connect_refusal(nil, "project" => "web")
    assert_nil entry.connect_refusal(nil, "organization" => "acme")
  end

  test "the organization and project take only what Sentry's own slug rules allow" do
    organization, project = IntegrationProvider.find("sentry").connect_fields

    %w[acme Acme-Co a1].each { |slug| assert_nil organization.refusal(slug), slug }
    %w[acme- -acme 123 a.b a_b acme/x].each { |slug| assert_match "letters, numbers and dashes", organization.refusal(slug), slug }
    assert organization.refusal("a" * 51)
    %w[web web_api check-out].each { |slug| assert_nil project.refusal(slug), slug }
    %w[Web 42 a.b web/x].each { |slug| assert_match "lowercase letters", project.refusal(slug), slug }
    assert_nil project.refusal("")
  end

  test "a connection held to no organization, or a resource no project could be called, is refused with what to do" do
    @sentry.update!(settings: { "server_url" => "https://mcp.sentry.dev/mcp" })
    assert_match "connect Sentry again and give its organization", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web")

    @sentry.update!(settings: { "server_url" => "https://mcp.sentry.dev/mcp/acme" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "api-id",
                                  name: "Checkout API", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
    assert_match "cannot be the name of a Sentry project", unroutable(Integrations::Capabilities::ERRORS, "resource" => "Checkout API")
  end

  test "Sentry is passed over when its tool is off, and says what Halon can do through it" do
    @issues.update!(enabled: false)
    assert_match "no connection offers errors", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web")

    assert_equal "Halon can see what was deployed and read its errors for the services on the map that Sentry watches, by their name in Sentry, " \
                 "through the tools you switch on. It also uses Sentry's other tools that you switch on.",
                 Integrations::Capabilities.halon_sentence("sentry", "Sentry")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
