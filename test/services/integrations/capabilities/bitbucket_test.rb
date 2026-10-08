require "test_helper"

class Integrations::Capabilities::BitbucketTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    bitbucket = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket", slug: "bitbucket")
    @row = bitbucket.integration_environments.create!
    %w[job_log recent_deployments ci_status].each do |name|
      bitbucket.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "bitbucket", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web",
                                  name: "acme/web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "a repository's build log, deployments and CI status are asked of Bitbucket by the repository's path" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "acme/web", "text" => "PG", "minutes" => 30, "limit" => 50)
    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "acme/web", "limit" => 5)
    status = resolve(Integrations::Capabilities::STATUS, "resource" => "acme/web")

    assert_equal [ "job_log", { "repo" => "acme/web", "text" => "PG", "minutes" => 30, "limit" => 50 } ], [ logs.tool.name, logs.arguments ]
    assert_equal [ "recent_deployments", { "repo" => "acme/web", "limit" => 5 } ], [ deploys.tool.name, deploys.arguments ]
    assert_equal [ "ci_status", { "repo" => "acme/web" } ], [ status.tool.name, status.arguments ]
  end

  test "a repository only has build logs, so any other stream is refused in words" do
    message = assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "acme/web", "stream" => "app") }.message

    assert_equal "Bitbucket keeps the build logs of acme/web, so stream must be build. Ask the platform that runs it for the rest.", message
  end

  test "Bitbucket keeps no metrics, traces or errors, answers its CI runs' history, and wraps none of its own tools" do
    adapter = Integrations::Capabilities.adapter_for("bitbucket")

    assert_equal [ Integrations::Capabilities::LOGS, Integrations::Capabilities::DEPLOYS, Integrations::Capabilities::STATUS, Integrations::Capabilities::HISTORY ],
                 adapter.capabilities
    assert_not adapter.wraps?("ci_status")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)
end
