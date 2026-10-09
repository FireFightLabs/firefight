require "test_helper"

class Operator::WorkspacesTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "nobody but a verified operator sees a workspace's sandbox or moves it" do
    sign_in(users(:bob), @workspace)

    get operator_workspace_path(@workspace)
    assert_response :not_found
    post sandbox_operator_workspace_path(@workspace), params: { placement: SandboxProviders::NORTHFLANK }
    assert_response :not_found
    assert_nil @workspace.reload.sandbox_provider
  end

  test "an operator holds a workspace to one provider and lets it follow the deployment again, each with a toast" do
    as_operator

    post sandbox_operator_workspace_path(@workspace), params: { placement: SandboxProviders::NORTHFLANK }
    assert_equal SandboxProviders::NORTHFLANK, @workspace.reload.sandbox_provider
    assert_equal "#{@workspace.name}'s code sandboxes now run only on Northflank.", flash[:notice]

    post sandbox_operator_workspace_path(@workspace), params: { placement: Operator::WorkspaceSandbox::FOLLOW_DEPLOYMENT }
    assert_nil @workspace.reload.sandbox_provider
    assert_equal "#{@workspace.name}'s code sandboxes follow the deployment's providers again.", flash[:notice]

    post sandbox_operator_workspace_path(@workspace), params: { placement: "fly" }
    assert_match "fly is not a sandbox provider", flash[:alert]
    assert_nil @workspace.reload.sandbox_provider
  end

  test "a workspace shows its failovers, and each code fix's sandbox cost beside its AI cost" do
    as_operator
    session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "claude", repository: "acme/api", budget_micros: 2_000_000,
                                       spent_micros: 420_000, expires_at: 30.minutes.from_now, token_digest: "digest-1", box_key: "investigation-9",
                                       created_at: 20.minutes.ago)
    CodeBox.create!(workspace: @workspace, key: "investigation-9", provider: SandboxProviders::NORTHFLANK, box_ref: "box-1", address: "http://box",
                    secret: "k", last_used_at: Time.current, created_at: 25.minutes.ago, box_started_at: 25.minutes.ago, stopped_at: 5.minutes.ago,
                    running_seconds: 1_200, size: "nf-compute-400", hourly_micros: 133_000, failed_over_from: SandboxProviders::BOAT,
                    failover_reason: "boat.dev answered 503: No machine of this type is ready. (no_ready_machine)")

    get operator_workspace_path(@workspace), headers: inertia_headers

    props = inertia_props
    assert_equal Operator::WorkspaceSandbox::FOLLOW_DEPLOYMENT, props["placement"]
    assert_equal [ "boat.dev", "Northflank" ], props["failovers"].first.values_at("from", "to")
    fix = props["fixes"].find { |row| row["id"] == session.id }
    assert_equal [ 420_000, 44_333, 1_200, [ "Northflank" ] ], fix.values_at("aiMicros", "sandboxMicros", "sandboxSeconds", "providers")

    get operator_root_path, headers: inertia_headers
    item = inertia_props["attentionItems"].find { |each| each["kind"] == Operator::Attention::KIND_SANDBOX_FAILOVER }
    assert_equal operator_workspace_path(@workspace), item["href"]
  end

  test "workspaces are listed with where their boxes run and what they cost" do
    as_operator
    @workspace.update!(sandbox_provider: SandboxProviders::NORTHFLANK)

    get operator_workspaces_path, headers: inertia_headers

    row = inertia_props["workspaces"].find { |each| each["id"] == @workspace.id }
    assert_equal [ "Northflank", true ], row.values_at("placement", "held")
  end

  private

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end
end
