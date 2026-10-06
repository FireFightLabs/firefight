require "test_helper"

class Integrations::Capabilities::CircleciTest < ActiveSupport::TestCase
  LIST_RUNS = { "type" => "object", "properties" => { "project_slug" => { "type" => "string" }, "branch" => { "type" => "string" }, "status" => { "type" => "string" } } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    circleci = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "circleci", name: "CircleCI", slug: "circleci",
                                               settings: { "server_url" => "https://mcp.circleci.com/v1/mcp" })
    @circleci_row = circleci.integration_environments.create!
    @list_runs = circleci.tools.create!(name: "list_runs", description: "Runs", read_only: true, enabled: true, params_schema: LIST_RUNS)
    repository("github", "acme/web", details: { "branch" => "main" })
    repository("bitbucket", "acme/billing")
  end

  test "CircleCI answers how a GitHub or Bitbucket repository's builds stand, by its project slug and default branch" do
    web = resolve(Integrations::Capabilities::STATUS, "resource" => "acme/web")

    assert_equal [ @circleci_row, "list_runs" ], [ web.environment_row, web.tool.name ]
    assert_equal({ "project_slug" => "gh/acme/web", "branch" => "main" }, web.arguments)
    assert_equal({ "project_slug" => "bb/acme/billing" }, resolve(Integrations::Capabilities::STATUS, "resource" => "acme/billing").arguments)
  end

  test "the arguments follow the parameters the server reports, and one it does not know is refused in words" do
    @list_runs.update!(params_schema: { "type" => "object", "properties" => { "projectSlug" => { "type" => "string" } } })
    assert_equal({ "projectSlug" => "gh/acme/web" }, resolve(Integrations::Capabilities::STATUS, "resource" => "acme/web").arguments)

    @list_runs.update!(params_schema: { "type" => "object", "properties" => { "org" => { "type" => "string" } } })
    assert_match "takes its project in a way Firefight does not know", unroutable(Integrations::Capabilities::STATUS, "resource" => "acme/web")
  end

  test "CircleCI answers no logs, since a job's log needs ids only earlier calls give" do
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "acme/web")
  end

  test "the platform answers a repository's status by default, CircleCI when named, and both under all" do
    gitlab = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab", slug: "gitlab")
    gitlab_row = gitlab.integration_environments.create!(credentials: { token: "x" }.to_json)
    gitlab.tools.create!(name: "ci_status", description: "CI", read_only: true, enabled: true, params_schema: { "type" => "object" })
    repository("gitlab", "acme/platform/api", holder: gitlab_row)

    assert_equal gitlab_row, resolve(Integrations::Capabilities::STATUS, "resource" => "acme/platform/api").environment_row
    assert_match "named by CircleCI's own ids", unroutable(Integrations::Capabilities::STATUS, "resource" => "acme/platform/api", "connection" => "circleci")

    answers = Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::STATUS, { "resource" => "acme/platform/api", "connection" => "all" }, principal: map_reader)
    assert_equal "gitlab.ci_status", answers.grep(Integrations::Capabilities::Call).sole.tool.action_key
    assert_equal @circleci_row, answers.grep(Integrations::Capabilities::Refused).sole.environment_row
  end

  test "CircleCI is not asked when its tool is off or the caller may not run it" do
    others = Integration::Tool.in_workspace(@workspace).reject { |tool| tool.integration.provider == "circleci" }
    assert_raises(Integrations::Capabilities::Unroutable) do
      Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "acme/web" }, others, principal: map_reader)
    end

    @list_runs.update!(enabled: false)
    assert_match "no connection offers status", unroutable(Integrations::Capabilities::STATUS, "resource" => "acme/web")
  end

  test "a person reads what Halon can do through CircleCI" do
    assert_equal [ Integrations::Capabilities::STATUS ], Integrations::Capabilities::Circleci.capabilities
    assert_empty Integrations::Capabilities::Circleci::WRAPPED
  end

  private

  def repository(provider, path, details: {}, holder: nil)
    hosts = { "github" => "https://github.com", "bitbucket" => "https://bitbucket.org", "gitlab" => "https://gitlab.com" }
    ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: path.split("/").first, kind: ResourceMap::KIND_REPOSITORY,
                                  external_id: path, name: path, url: "#{hosts.fetch(provider)}/#{path}", details: details, integration_environment: holder,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
