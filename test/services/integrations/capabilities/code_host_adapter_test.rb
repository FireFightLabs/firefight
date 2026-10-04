require "test_helper"

class Integrations::Capabilities::CodeHostAdapterTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github_row = code_host("github", "GitHub", "acme/web")
    @gitlab_row = code_host("gitlab", "GitLab", "acme/platform/api")
  end

  test "GitHub and GitLab answer a repository's build log, deployments and CI status by its path" do
    github_logs = resolve(Integrations::Capabilities::LOGS, "resource" => "acme/web", "text" => "PoolExhausted", "minutes" => 60)
    gitlab_status = resolve(Integrations::Capabilities::STATUS, "resource" => "acme/platform/api")
    gitlab_deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "acme/platform/api", "limit" => 5)

    assert_equal [ @github_row, "job_log", { "repo" => "acme/web", "text" => "PoolExhausted", "minutes" => 60 } ],
                 [ github_logs.environment_row, github_logs.tool.name, github_logs.arguments ]
    assert_equal [ @gitlab_row, "ci_status", { "repo" => "acme/platform/api" } ], [ gitlab_status.environment_row, gitlab_status.tool.name, gitlab_status.arguments ]
    assert_equal({ "repo" => "acme/platform/api", "limit" => 5 }, gitlab_deploys.arguments)
  end

  test "a repository only keeps build logs, so another stream is refused in the host's words" do
    error = assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "acme/platform/api", "stream" => "requests") }

    assert_equal "GitLab keeps the build logs of acme/platform/api, so stream must be build. Ask the platform that runs it for the rest.", error.message
  end

  test "a code host wraps none of its tools, so Halon keeps every one, and its details say what it answers for its repositories" do
    assert_not Integrations::Capabilities.adapter_for("github").wraps?("recent_deployments")
    assert_equal "Halon can read their build logs, see what was deployed, and check how their CI stands for the repositories GitLab puts on the map, " \
                 "through the tools you switch on. It also uses GitLab's other tools that you switch on.", Integrations::Capabilities.halon_sentence("gitlab", "GitLab")
    assert_equal "Halon can check how their CI stands for the repositories on the map that CircleCI builds, through the tools you switch on. " \
                 "It also uses CircleCI's other tools that you switch on.", Integrations::Capabilities.halon_sentence("circleci", "CircleCI")
  end

  test "GitHub answers a repository's CI status by default when CircleCI builds it too, and CircleCI answers when named" do
    circleci = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "circleci", name: "CircleCI", slug: "circleci",
                                               settings: { "server_url" => "https://mcp.circleci.com/v1/mcp" })
    circleci_row = circleci.integration_environments.create!
    circleci.tools.create!(name: "list_runs", description: "Runs", read_only: true, enabled: true,
                           params_schema: { "type" => "object", "properties" => { "project_slug" => { "type" => "string" } } })

    assert_equal @github_row, resolve(Integrations::Capabilities::STATUS, "resource" => "acme/web").environment_row
    named = resolve(Integrations::Capabilities::STATUS, "resource" => "acme/web", "connection" => "circleci")
    assert_equal [ circleci_row, { "project_slug" => "gh/acme/web" } ], [ named.environment_row, named.arguments ]
  end

  private

  def code_host(provider, name, repository, page = "https://#{provider}.com/#{repository}")
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: provider)
    row = integration.integration_environments.create!
    Integrations::Capabilities::CodeHostAdapter::TOOLS.each_value do |tool|
      integration.tools.create!(name: tool, description: tool, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: repository.split("/").first, kind: ResourceMap::KIND_REPOSITORY,
                                  external_id: repository, name: repository, url: page, integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
    row
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)
end
