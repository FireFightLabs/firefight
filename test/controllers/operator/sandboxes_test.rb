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

  test "an operator adopts a box with no record that says whose it is, and it is billed from when it started and used by its run" do
    as_operator
    key = "investigation-#{SecureRandom.uuid}"
    started = 50.minutes.ago
    seen("bx_lost", first_seen_at: started, owner: [ @workspace.id, key ])
    provider = Integrations::Sandboxes::Boat.new(api: Integrations::BoatApi.new)
    provider.expects(:reclaim).with("bx_lost").returns(Integrations::Sandboxes::Box.new(ref: "bx_lost", address: "https://lost.on.boat.dev?_token=gate", key: "k-new"))
    Integrations::Sandboxes.stubs(:provider).with(SandboxProviders::BOAT).returns(provider)

    get operator_sandboxes_path, headers: inertia_headers
    box = inertia_props["boxes"].find { |each| each["ref"] == "bx_lost" }
    assert_equal [ [ "rogue" ], @workspace.name, nil ], box.values_at("flags", "workspaceName", "adoptBlockedReason")
    assert_equal "Investigation", box.dig("origin", "label")

    post adopt_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_lost" }

    assert_equal "Adopted halon-box-bx_lost for #{@workspace.name}. It stops once nothing uses it for 1 hour.", flash[:notice]
    adopted = CodeBox.live.find_by!(key: key)
    assert_equal [ @workspace, SandboxProviders::BOAT, "bx_lost", "k-new", "https://lost.on.boat.dev?_token=gate", "default", 36_000 ],
                 [ adopted.workspace, adopted.provider, adopted.box_ref, adopted.secret, adopted.reach_address, adopted.size, adopted.hourly_micros ]
    assert_in_delta started, adopted.box_started_at, 1
    assert_equal [ "adopt", "bx_lost", "#{@operator.email} (operator)" ], Operator::SandboxAction.find_by!(ref: "bx_lost").then { |action| [ action.action, action.ref, action.operator ] }

    get operator_sandboxes_path, headers: inertia_headers
    box = inertia_props["boxes"].find { |each| each["ref"] == "bx_lost" }
    assert_equal [ [], true ], box.values_at("flags", "recorded")
    assert_operator box["costMicros"], :>=, 29_000, "the time it ran with no record is billed too"
  end

  test "a box whose stop failed at the provider is adopted for the run its stopped record names, billed from when that record stopped" do
    as_operator
    stopped = record("bx_unstopped", created_at: 2.hours.ago).tap { |row| row.update!(stopped_at: 40.minutes.ago) }
    seen("bx_unstopped", first_seen_at: 2.hours.ago)
    provider = Integrations::Sandboxes::Boat.new(api: Integrations::BoatApi.new)
    provider.stubs(:reclaim).returns(Integrations::Sandboxes::Box.new(ref: "bx_unstopped", address: "https://b", key: "k-new"))
    Integrations::Sandboxes.stubs(:provider).returns(provider)

    post adopt_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_unstopped" }

    adopted = CodeBox.live.find_by!(key: stopped.key)
    assert_not_equal stopped.id, adopted.id
    assert_in_delta stopped.stopped_at, adopted.box_started_at, 1
    get operator_sandboxes_path, headers: inertia_headers
    assert_equal [], inertia_props["boxes"].find { |each| each["ref"] == "bx_unstopped" }["flags"]
  end

  test "a box that cannot be matched, whose workspace is gone or whose run has another box is refused with why, and only stop or delete are left" do
    as_operator
    taken = "conversation-#{SecureRandom.uuid}"
    record("bx_current", key: taken)
    seen("bx_current")
    seen("bx_nameless", first_seen_at: 1.hour.ago)
    seen("bx_orphan", first_seen_at: 1.hour.ago, owner: [ SecureRandom.uuid, "investigation-#{SecureRandom.uuid}" ])
    seen("bx_second", first_seen_at: 1.hour.ago, owner: [ @workspace.id, taken ])
    Integrations::SandboxInventory.expects(:adopt!).never

    get operator_sandboxes_path, headers: inertia_headers
    reasons = inertia_props["boxes"].to_h { |box| [ box["ref"], box["adoptBlockedReason"] ] }
    assert_equal "Nothing on this box says which workspace or run started it, so it can only be stopped or deleted.", reasons["bx_nameless"]
    assert_equal "The workspace this box was started for no longer exists, so it can only be stopped or deleted.", reasons["bx_orphan"]
    assert_equal "The run this box was started for has another box now, so this one can only be stopped or deleted.", reasons["bx_second"]
    assert_equal "Firefight already has a record of this box.", reasons["bx_current"]

    post adopt_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_nameless" }
    assert_equal reasons["bx_nameless"], flash[:alert]
    post adopt_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_second" }
    assert_equal reasons["bx_second"], flash[:alert]
    assert_not Operator::SandboxAction.exists?(action: Operator::SandboxAction::ADOPT)
  end

  test "a provider that cannot hand a box back is said, and nothing is recorded for the run" do
    as_operator
    key = "investigation-#{SecureRandom.uuid}"
    seen("bx_lost", first_seen_at: 1.hour.ago, owner: [ @workspace.id, key ])
    provider = Integrations::Sandboxes::Boat.new(api: Integrations::BoatApi.new)
    provider.stubs(:reclaim).raises(Integrations::BoatApi::NotFound, "boat.dev answered 404: Sandbox not found. (not_found)")
    Integrations::Sandboxes.stubs(:provider).returns(provider)

    post adopt_operator_sandboxes_path, params: { provider: SandboxProviders::BOAT, ref: "bx_lost" }

    assert_equal "boat.dev answered 404: Sandbox not found. (not_found)", flash[:alert]
    assert_not CodeBox.exists?(key: key)
    assert_equal "boat.dev answered 404: Sandbox not found. (not_found)", Operator::SandboxAction.find_by!(ref: "bx_lost", action: Operator::SandboxAction::ADOPT).outcome
  end

  private

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end

  def seen(ref, phase: ProviderSandbox::PHASE_RUNNING, state: "idle", first_seen_at: 30.minutes.ago, owner: nil)
    ProviderSandbox.create!(provider: SandboxProviders::BOAT, kind: ProviderSandbox::KIND_BOX, ref: ref, name: "halon-box-#{ref}", purpose: ProviderSandbox::PURPOSE_RUN,
                            phase: phase, state: state, size: "default", started_at: first_seen_at, provider_updated_at: first_seen_at,
                            first_seen_at: first_seen_at, last_seen_at: Time.current, owner_workspace_id: owner&.first, owner_key: owner&.last)
  end

  def record(ref, key: "conversation-#{SecureRandom.uuid}", last_used_at: Time.current, created_at: 30.minutes.ago)
    CodeBox.create!(workspace: @workspace, key: key, provider: SandboxProviders::BOAT, box_ref: ref, address: "https://a", secret: "k",
                    last_used_at: last_used_at, created_at: created_at, box_started_at: created_at, size: "default", hourly_micros: 36_000)
  end
end
