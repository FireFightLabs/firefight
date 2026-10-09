require "test_helper"

class Operator::SandboxesTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    SandboxProviderRead.read!(SandboxProviders::BOAT)
    @investigation = Investigation.where(workspace: @workspace).first
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "nobody but a verified operator sees the sandboxes or acts on them" do
    sign_in(users(:bob), @workspace)
    seen("bx_rogue", first_seen_at: 1.hour.ago)
    Integrations::SandboxInventory.expects(:delete!).never

    get operator_sandboxes_path
    assert_response :not_found
    post clean_up_operator_sandboxes_path
    assert_response :not_found
  end

  test "each box is set against its record, so one with no record, overdue, failed, stuck or gone stands out" do
    as_operator
    recorded = record("bx_ok", key: "investigation-#{@investigation&.id || 'x'}")
    seen("bx_ok")
    seen("bx_rogue", first_seen_at: 1.hour.ago)
    seen("bx_new", first_seen_at: 2.minutes.ago)
    seen("bx_failed", phase: ProviderSandbox::PHASE_FAILED, state: "error")
    seen("bx_stuck", phase: ProviderSandbox::PHASE_STARTING, state: "provisioning", first_seen_at: 1.hour.ago)
    record("bx_idle", last_used_at: 3.hours.ago).tap { seen("bx_idle") }
    record("bx_vanished", created_at: 1.hour.ago)
    SandboxProviderRead.read!(SandboxProviders::BOAT)

    get operator_sandboxes_path, headers: inertia_headers

    flags = inertia_props["boxes"].to_h { |box| [ box["ref"], box["flags"] ] }
    assert_equal [], flags["bx_ok"]
    assert_equal [ "rogue" ], flags["bx_rogue"]
    assert_equal [], flags["bx_new"], "a box the app is still writing down is not called rogue"
    assert_includes flags["bx_failed"], "failed"
    assert_includes flags["bx_stuck"], "stuck"
    assert_equal [ "overdue" ], flags["bx_idle"]
    assert_equal [ "missing" ], flags["bx_vanished"]
    box = inertia_props["boxes"].find { |each| each["ref"] == "bx_ok" }
    assert_equal @workspace.name, box["workspaceName"]
    assert_not box.key?("address"), "a box's address never reaches the page"
    assert_equal recorded.workspace.name, box["workspaceName"]
    assert_operator inertia_props.dig("totals", "rogue"), :>=, 1

    get operator_root_path, headers: inertia_headers
    rogue = inertia_props["attentionItems"].find { |item| item["kind"] == Operator::Attention::KIND_SANDBOX_ROGUE }
    assert_equal operator_sandboxes_path, rogue["href"]
  end

  test "a kept copy with no row and one past the free ten are shown with what they cost" do
    as_operator
    ProviderSandbox.create!(provider: SandboxProviders::BOAT, kind: ProviderSandbox::KIND_SNAPSHOT, ref: "halon-kept-lost", purpose: ProviderSandbox::PURPOSE_PREPARED,
                            phase: ProviderSandbox::PHASE_READY, monthly_micros: 1_700_000, first_seen_at: 2.hours.ago, last_seen_at: Time.current)
    PreparedCopy.kept!(SandboxProviders::BOAT, @workspace, "acme/app", "key-1", kept_ref: "halon-kept-known", commit: "abc")
    ProviderSandbox.create!(provider: SandboxProviders::BOAT, kind: ProviderSandbox::KIND_SNAPSHOT, ref: "halon-kept-known", purpose: ProviderSandbox::PURPOSE_PREPARED,
                            phase: ProviderSandbox::PHASE_READY, monthly_micros: 0, first_seen_at: 2.hours.ago, last_seen_at: Time.current)

    get operator_sandboxes_path, headers: inertia_headers

    copies = inertia_props["copies"].index_by { |copy| copy["ref"] }
    assert_equal [ [ "rogue" ], 1_700_000 ], copies["halon-kept-lost"].values_at("flags", "monthlyMicros")
    assert_equal [ [], "acme/app" ], copies["halon-kept-known"].values_at("flags", "repository")
  end

  test "an operator stops and deletes a box and cleans up rogue ones, each with a toast and recorded under their name" do
    as_operator
    record("bx_live")
    seen("bx_live")
    seen("bx_rogue", first_seen_at: 1.hour.ago)
    Integrations::SandboxInventory.expects(:stop!).with(SandboxProviders::BOAT, "bx_live")
    Integrations::SandboxInventory.expects(:delete!).with(SandboxProviders::BOAT, ProviderSandbox::KIND_BOX, "bx_rogue").twice

    post stop_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_live" }
    assert_equal "Stopping halon-box-bx_live.", flash[:notice]
    post delete_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_rogue", kind: ProviderSandbox::KIND_BOX }
    assert_equal "Deleted bx_rogue for good.", flash[:notice]
    post clean_up_operator_sandboxes_path
    assert_match "Deleted 1 rogue", flash[:notice]

    recorded = Operator::SandboxAction.order(:created_at).map { |action| [ action.action, action.ref, action.operator ] }
    assert_equal [ [ "stop", "bx_live", "#{@operator.email} (operator)" ], [ "delete", "bx_rogue", "#{@operator.email} (operator)" ],
                   [ "clean_up", "bx_rogue", "#{@operator.email} (operator)" ] ], recorded
  end

  test "an action a box cannot take is refused with why, and a provider's refusal is said" do
    as_operator
    seen("bx_stopped", phase: ProviderSandbox::PHASE_STOPPED, state: "archived")
    seen("bx_running", first_seen_at: 1.hour.ago)

    post stop_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_stopped" }
    assert_equal "This box is not running.", flash[:alert]

    Integrations::SandboxInventory.stubs(:delete!).raises(Integrations::BoatApi::Forbidden, "boat.dev answered 403: Not allowed. (forbidden)")
    post delete_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_running", kind: ProviderSandbox::KIND_BOX }
    assert_equal "boat.dev answered 403: Not allowed. (forbidden)", flash[:alert]
    assert_equal "boat.dev answered 403: Not allowed. (forbidden)", Operator::SandboxAction.find_by!(ref: "bx_running").outcome
  end

  private

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end

  def seen(ref, phase: ProviderSandbox::PHASE_RUNNING, state: "idle", first_seen_at: 30.minutes.ago)
    ProviderSandbox.create!(provider: SandboxProviders::BOAT, kind: ProviderSandbox::KIND_BOX, ref: ref, name: "halon-box-#{ref}", purpose: ProviderSandbox::PURPOSE_RUN,
                            phase: phase, state: state, size: "default", started_at: first_seen_at, provider_updated_at: first_seen_at,
                            first_seen_at: first_seen_at, last_seen_at: Time.current)
  end

  def record(ref, key: "conversation-#{SecureRandom.uuid}", last_used_at: Time.current, created_at: 30.minutes.ago)
    CodeBox.create!(workspace: @workspace, key: key, provider: SandboxProviders::BOAT, box_ref: ref, address: "https://a", secret: "k",
                    last_used_at: last_used_at, created_at: created_at, box_started_at: created_at, size: "default", hourly_micros: 36_000)
  end
end
