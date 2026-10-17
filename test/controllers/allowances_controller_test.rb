require "test_helper"

# What Halon may do without asking is edited under Settings, Workspace, by an admin, and every change says so.
class AllowancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    @merge = github.tools.create!(name: "merge_pull_request", description: "Merge", enabled: true, read_only: false, params_schema: {})
    @production = catalog_entries(:production_env)
    sign_in(users(:alice), @workspace)
  end

  test "an entry is added by whoever set it and named in the notice" do
    post allowances_url, params: { allowance: { capability: Integrations::Capabilities::ROLLBACK, environment: @production.id } }

    assert_redirected_to settings_workspace_path
    assert_equal "\"Roll back deploys in Production\" was added to what Halon may do without asking.", flash[:notice]
    entry = @workspace.allowances.sole
    assert_equal [ Integrations::Capabilities::ROLLBACK, @production, workspace_memberships(:alice_workspace_one) ], [ entry.capability, entry.environment, entry.created_by ]
  end

  test "a tool is named by its key, and one that changes access is refused with why" do
    post allowances_url, params: { allowance: { action_key: @merge.action_key } }
    assert_equal "\"Merge pull request on GitHub\" was added to what Halon may do without asking.", flash[:notice]

    secret = @merge.integration.tools.create!(name: "set_actions_secret", description: "Set", enabled: true, read_only: false, params_schema: {})
    post allowances_url, params: { allowance: { action_key: secret.action_key } }
    assert_equal 1, @workspace.allowances.count
  end

  test "editing, turning off and on say what changed" do
    entry = @workspace.allowances.create!(capability: Integrations::Capabilities::SCALE)

    patch allowance_url(entry), params: { allowance: { capability: Integrations::Capabilities::SCALE, environment: @production.id } }
    assert_equal "\"Scale services in Production\" was updated.", flash[:notice]

    patch allowance_url(entry), params: { allowance: { enabled: false } }
    assert_equal "\"Scale services in Production\" is off.", flash[:notice]
    assert_not entry.reload.enabled?

    patch allowance_url(entry), params: { allowance: { enabled: true } }
    assert_equal "\"Scale services in Production\" is on.", flash[:notice]
  end

  test "an unused entry is deleted, and one Halon acted under is refused with why" do
    entry = @workspace.allowances.create!(action: @merge.ability_action)
    delete allowance_url(entry)
    assert_equal "\"Merge pull request on GitHub\" was deleted.", flash[:notice]
    assert_equal 0, @workspace.allowances.count

    used = @workspace.allowances.create!(action: @merge.ability_action)
    Ability::Invocation.create!(workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice", action_key: @merge.action_key,
                                decision: Ability::Invocation::DECISION_ALLOW, idempotency_key: SecureRandom.uuid, allowance: used)
    delete allowance_url(used)
    assert_equal "Halon made 1 change under this, so it stays for the record. Turn it off instead.", flash[:alert]
    assert Ability::Allowance.exists?(used.id)
  end

  test "a member may not change the list" do
    sign_in(users(:bob), @workspace)
    post allowances_url, params: { allowance: { capability: Integrations::Capabilities::ROLLBACK } }

    assert_equal 0, @workspace.allowances.count
  end

  test "the workspace page lists the entries and what a new one can name" do
    @workspace.allowances.create!(action: @merge.ability_action)

    get settings_workspace_url, headers: inertia_headers

    assert_response :success
    props = inertia_props
    assert_equal [ "Merge pull request on GitHub" ], props["allowances"].map { |entry| entry["name"] }
    assert_includes props["allowanceTools"].map { |choice| choice["value"] }, @merge.action_key
    assert props["settings"]["safeChangesWithoutAsking"]
  end
end
