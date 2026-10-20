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

  test "a connection through the hosted server answers no logs of a repository, since a job's log needs ids only earlier calls give" do
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "acme/web")
  end

  test "a connection with an API token finds the project of any repository, a GitLab one too, from its address" do
    row = native_connection("list_runs" => { "project" => { "type" => "string" }, "repository" => { "type" => "string" } },
                            "ci_status" => { "project" => { "type" => "string" }, "repository" => { "type" => "string" } },
                            "ci_runs" => { "project" => { "type" => "string" }, "repository" => { "type" => "string" } })
    gitlab = repository("gitlab", "acme/platform/api")

    status = resolve(Integrations::Capabilities::STATUS, "resource" => "acme/platform/api", "connection" => "circleapi")
    assert_equal [ row, "ci_status", { "repository" => gitlab.url } ], [ status.environment_row, status.tool.name, status.arguments ]
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "acme/platform/api", "connection" => "circleapi")
    assert_equal [ "ci_runs", { "repository" => gitlab.url } ], [ history.tool.name, history.arguments ]
  end

  test "a project on the map answers its runs, status, job logs, deploys and a rollback by its id" do
    row = native_connection("list_runs" => {}, "ci_status" => {}, "ci_runs" => {}, "get_job_logs" => {}, "list_deploys" => {}, "rollback_deploy" => {})
    ResourceMap::Resource.create!(workspace: @workspace, provider: "circleci", account: "acme", kind: ResourceMap::KIND_PIPELINE, external_id: "p-1",
                                  name: "gh/acme/web", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
    capability = Integrations::Capabilities

    assert_equal [ "ci_runs", { "project" => "p-1", "run" => "r-9" } ], routed(capability::HISTORY, "resource" => "gh/acme/web", "run" => "r-9")
    assert_equal [ "ci_status", { "project" => "p-1" } ], routed(capability::STATUS, "resource" => "gh/acme/web")
    assert_equal [ "get_job_logs", { "project" => "p-1", "text" => "boom", "run" => "r-9" } ], routed(capability::LOGS, "resource" => "gh/acme/web", "text" => "boom", "run" => "r-9")
    assert_equal [ "list_deploys", { "project" => "p-1" } ], routed(capability::DEPLOYS, "resource" => "gh/acme/web")
    assert_equal [ "rollback_deploy", { "project" => "p-1", "component" => "api", "environment" => "production", "version" => "v1/2" } ],
                 routed(capability::ROLLBACK, "resource" => "gh/acme/web", "to" => "api/production/v1/2")
    assert_match "component/environment/version", unroutable(capability::ROLLBACK, "resource" => "gh/acme/web", "to" => "v41")
    assert_match "stream must be build", unroutable(capability::LOGS, "resource" => "gh/acme/web", "stream" => "app")
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
    capability = Integrations::Capabilities
    assert_equal [ capability::LOGS, capability::DEPLOYS, capability::STATUS, capability::HISTORY, capability::ROLLBACK ], capability::Circleci.capabilities
    assert_empty Integrations::Capabilities::Circleci::WRAPPED
  end

  private

  def repository(provider, path, details: {}, holder: nil)
    hosts = { "github" => "https://github.com", "bitbucket" => "https://bitbucket.org", "gitlab" => "https://gitlab.com" }
    ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: path.split("/").first, kind: ResourceMap::KIND_REPOSITORY,
                                  external_id: path, name: path, url: "#{hosts.fetch(provider)}/#{path}", details: details, integration_environment: holder,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def native_connection(tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "circleci", name: "CircleCI API", slug: "circleapi")
    row = integration.integration_environments.create!(credentials: { api_token: "x" }.to_json)
    tools.each do |name, properties|
      integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object", "properties" => properties })
    end
    row
  end

  def routed(key, given)
    call = resolve(key, given)
    [ call.tool.name, call.arguments ]
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
