require "test_helper"

# Where a hosted build sells a plan, starting it is a required step of setup. The workspace stays closed until a trial
# or the plan is running, the admin setting it up is sent to the step from anywhere, and nothing after it can be answered.
class SetupPlanTest < ActionDispatch::IntegrationTest
  setup do
    @owner = Workspace.sign_up!(name: "Trial Co", user: User.create!(email: "trial-#{SecureRandom.hex(4)}@example.com", name: "Tia Trial"))
    @workspace = @owner.workspace
    @backend = sell_plan!(path: "/plan/checkout")
  end

  test "setup opens on the plan step with the offer, though the workspace is closed until it starts" do
    sign_in(@owner.user, @workspace)

    get onboarding_checklist_path, headers: inertia_headers

    assert_response :success
    props = inertia_props
    assert_equal WorkspaceOnboarding::CHECKLIST_STEPS, props["steps"].pluck("key")
    assert_equal WorkspaceOnboarding::STATE_CURRENT, props["steps"].find { |step| step["key"] == WorkspaceOnboarding::STEP_PLAN }["state"]
    assert_equal({ "active" => false, "price" => "$99", "priceNote" => "Early adopter price", "included" => [ "Every feature" ],
                   "trialDays" => 14, "terms" => "Free for 14 days.", "summary" => nil, "startPath" => "/plan/checkout",
                   "startBlockedReason" => nil }, props["plan"])
  end

  test "the dashboard is not reachable until the plan starts, so the admin is sent back to the plan step" do
    sign_in(@owner.user, @workspace)

    get dashboard_path
    assert_redirected_to onboarding_checklist_path

    get settings_workspace_path
    assert_redirected_to onboarding_checklist_path
  end

  test "a member of a workspace waiting on its plan goes where the backend says, not to setup" do
    member = @workspace.workspace_memberships.create!(user: User.create!(email: "m-#{SecureRandom.hex(4)}@example.com", name: "Mo Member"), role: :member, joined_at: Time.current)
    sign_in(member.user, @workspace)

    get dashboard_path

    assert_redirected_to "/plan/checkout"
  end

  test "nothing after the plan step can be answered before it starts" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_HOUSE }
    assert_redirected_to onboarding_checklist_path
    assert_equal WorkspaceOnboarding::PLAN_FIRST, flash[:alert]
    assert_nil @workspace.onboarding.reload.ai_chosen_at

    post onboarding_checklist_permissions_path
    assert_equal WorkspaceOnboarding::PLAN_FIRST, flash[:alert]
    post onboarding_checklist_skip_slack_path
    assert_equal WorkspaceOnboarding::PLAN_FIRST, flash[:alert]
    assert_nil @workspace.onboarding.reload.chat_skipped_at
  end

  test "back from checkout with the trial running, the step is done and setup moves on to Halon's AI" do
    sign_in(@owner.user, @workspace)
    @backend.stage = :active

    get onboarding_checklist_path, headers: inertia_headers

    steps = inertia_props["steps"]
    assert_equal WorkspaceOnboarding::STATE_DONE, steps.find { |step| step["key"] == WorkspaceOnboarding::STEP_PLAN }["state"]
    assert_equal WorkspaceOnboarding::STEP_AI, steps.find { |step| step["state"] == WorkspaceOnboarding::STATE_CURRENT }["key"]
    assert_equal "Your trial runs until October 25, 2026.", inertia_props.dig("plan", "summary")

    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_HOUSE }
    assert_nil flash[:alert]
  end

  test "a plan that lapses before setup finishes closes the workspace and puts the plan step back up next" do
    sign_in(@owner.user, @workspace)
    @backend.stage = :lapsed

    get dashboard_path
    assert_redirected_to onboarding_checklist_path

    get onboarding_checklist_path, headers: inertia_headers
    assert_response :success
    assert_equal WorkspaceOnboarding::STEP_PLAN, inertia_props["steps"].find { |step| step["state"] == WorkspaceOnboarding::STATE_CURRENT }["key"]
  end

  test "a suspension still closes setup, whatever the plan" do
    @workspace.update!(suspended_at: Time.current, suspended_reason: Workspace::Suspension::SUSPENSION_MISUSE)
    sign_in(@owner.user, @workspace)

    get onboarding_checklist_path, headers: inertia_headers

    assert_response :forbidden
    assert_equal "errors/suspended", JSON.parse(response.body)["component"]
  end

  test "a workspace that finished setup before plans were sold is never sent back to it" do
    Entitlements.reset_backend!
    @workspace.onboarding.update!(checklist_completed_at: 1.day.ago)
    sign_in(@owner.user, @workspace)

    get dashboard_path, headers: inertia_headers

    assert_response :success
    get onboarding_checklist_path
    assert_redirected_to dashboard_path
  end
end
