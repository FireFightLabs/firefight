require "test_helper"

class Integration::CodeChangesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
  end

  test "a code host keeps no paths by default, so any change may be written" do
    assert_equal [], @github.protected_paths
    assert_nil @github.protected_paths_refusal("acme/api", [ ".github/workflows/release.yml", "app/models/pool.rb" ])
  end

  test "a list is saved trimmed, without blank or repeated lines, and a refused change names the paths and where the list is" do
    assert_nil @github.protect_paths!([ " .github/workflows/ ", "", "*.lock\ninfra/prod/**", "*.lock" ])

    assert_equal [ ".github/workflows/", "*.lock", "infra/prod/**" ], @github.reload.protected_paths
    assert_equal "Halon may not change .github/workflows/release.yml and Gemfile.lock in acme/api. An admin can change this under Integrations, GitHub, Code changes.",
                 @github.protected_paths_refusal("acme/api", [ "app/models/pool.rb", "Gemfile.lock", ".github/workflows/release.yml" ])
    assert_nil @github.protected_paths_refusal("acme/api", [ "app/models/pool.rb", ".github/CODEOWNERS" ])
  end

  test "the place names the connection when it is not named after its provider" do
    staging = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub staging")

    assert_equal "Integrations, GitHub, GitHub staging, Code changes", staging.protected_paths_place
  end

  test "a pattern that cannot be read is refused, and the list stays as it was" do
    @github.protect_paths!([ ".github/" ])

    assert_equal "../x reaches outside the repository. Give a path inside it, such as infra/prod/", @github.protect_paths!([ "docs/", "../x" ])
    assert_equal [ ".github/" ], @github.reload.protected_paths
    assert_equal "List at most 100 paths.", @github.protect_paths!((1..101).map { |number| "dir#{number}/" })
  end

  test "a connection that holds no code has no list" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://mcp.datadoghq.com" })

    refute datadog.holds_code?
    assert_match "holds no code", datadog.protect_paths!([ ".github/" ])
    assert @github.holds_code?
    assert @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab").holds_code?
    assert @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket").holds_code?
  end

  test "a coding agent is told the list of the code host whose repository it is on the map, or every code host's when the map does not say" do
    @github.protect_paths!([ ".github/" ])
    gitlab = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
    gitlab.protect_paths!([ "infra/**" ])
    row = gitlab.integration_environments.create!
    ResourceMap::Resource.create!(workspace: @workspace, provider: "gitlab", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web",
                                  name: "web", url: "https://gitlab.com/acme/web", integration_environment: row,
                                  first_seen_at: Time.current, last_seen_at: Time.current)

    assert_equal [ "infra/**" ], Integration.protected_paths_for(@workspace, "acme/web")
    assert_equal [ "infra/**" ], Integration.protected_paths_for(@workspace, "https://gitlab.com/acme/web")
    assert_equal [ ".github/", "infra/**" ], Integration.protected_paths_for(@workspace, "acme/unknown").sort
  end
end
