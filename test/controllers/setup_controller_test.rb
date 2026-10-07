require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  include AiAccountTestHelper

  setup do
    @owner = Workspace.sign_up!(name: "Setup Co", user: User.create!(email: "setup-#{SecureRandom.hex(4)}@example.com", name: "Sam Setup"))
    @workspace = @owner.workspace
    @onboarding = @workspace.onboarding
  end

  test "an admin is sent to setup from any page until it is done, and what the page meant to say comes along" do
    sign_in(@owner.user, @workspace)

    get settings_workspace_path
    assert_redirected_to onboarding_checklist_path

    get onboarding_checklist_path, headers: inertia_headers
    assert_response :success
    props = inertia_props
    assert_equal "setup/index", JSON.parse(response.body)["component"]
    assert_equal WorkspaceOnboarding::CHECKLIST_STEPS, props["steps"].pluck("key")
    assert_equal IntegrationProvider.category_list.map(&:slug), props["categories"].pluck("slug")
    assert_equal WorkspaceOnboarding::CATEGORY_REQUIRED, props["categories"].find { |category| category["slug"] == "code" }["unusedBlockedReason"]
    assert_equal WorkspaceOnboarding::NO_WORKING_ACCOUNT, props["aiChoices"][WorkspaceOnboarding::AI_ACCOUNT]
  end

  class StaysOpenController < InertiaController
    skip_before_action :block_inaccessible_workspace

    def show = head(:ok)
  end

  test "a page that stays open while the workspace is closed, such as where credits are bought, is not turned around" do
    sign_in(@owner.user, @workspace)

    with_routing do |routes|
      routes.draw { get "/stays-open", to: "setup_controller_test/stays_open#show" }

      get "/stays-open"
    end

    assert_response :success
  end

  test "the flash a redirected page carried reaches setup" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_HOUSE }
    assert_redirected_to onboarding_checklist_path
    assert_equal "Halon will use the AI keys this Firefight runs on.", flash[:notice]
  end

  test "a member goes to the dashboard, never to setup" do
    member = @workspace.workspace_memberships.create!(user: User.create!(email: "mem-#{SecureRandom.hex(4)}@example.com", name: "Mel Member"), role: :member, joined_at: Time.current)
    sign_in(member.user, @workspace)

    get dashboard_path
    assert_response :success

    get onboarding_checklist_path
    assert_redirected_to dashboard_path
  end

  test "Halon's AI cannot be an own account until one passes its check" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_ACCOUNT }
    assert_equal WorkspaceOnboarding::NO_WORKING_ACCOUNT, flash[:alert]
    assert_nil @onboarding.reload.ai_chosen_at

    add_ai_account!(@workspace).checked!
    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_ACCOUNT }
    assert_equal WorkspaceOnboarding::AI_ACCOUNT, @onboarding.reload.ai_choice
  end

  test "a choice this Firefight does not offer is refused" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_ai_path, params: { choice: WorkspaceOnboarding::AI_CREDITS }

    assert_equal "Pick how Halon pays for its AI.", flash[:alert]
    assert_nil @onboarding.reload.ai_chosen_at
  end

  test "a required category is answered only by connecting, another may be skipped" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_category_path("code"), params: { answer: WorkspaceOnboarding::ANSWER_UNUSED }
    assert_equal WorkspaceOnboarding::CATEGORY_REQUIRED, flash[:alert]

    post onboarding_checklist_category_path("code"), params: { answer: WorkspaceOnboarding::ANSWER_CONNECTED }
    assert_equal WorkspaceOnboarding::NOTHING_CONNECTED, flash[:alert]

    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    post onboarding_checklist_category_path("code"), params: { answer: WorkspaceOnboarding::ANSWER_CONNECTED }
    assert_equal "Code is set.", flash[:notice]

    post onboarding_checklist_category_path("issues"), params: { answer: WorkspaceOnboarding::ANSWER_UNUSED }
    assert_equal "Issues skipped.", flash[:notice]

    assert_equal({ "code" => WorkspaceOnboarding::ANSWER_CONNECTED, "issues" => WorkspaceOnboarding::ANSWER_UNUSED }, @onboarding.reload.stack_answers)
  end

  test "an unknown category is refused" do
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_category_path("toasters"), params: { answer: WorkspaceOnboarding::ANSWER_UNUSED }

    assert_equal "That is not a category of integrations.", flash[:alert]
  end

  test "Not now on Slack, the last step left, finishes setup and opens the dashboard" do
    @onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current, permissions_reviewed_at: Time.current,
                        halon_answered_at: Time.current)
    sign_in(@owner.user, @workspace)

    post onboarding_checklist_skip_slack_path

    assert_redirected_to dashboard_path
    assert_equal SetupController::DONE, flash[:notice]
    assert @onboarding.reload.checklist_completed_at

    get dashboard_path
    assert_response :success
  end

  test "a page visit after the last step finished elsewhere opens normally" do
    @onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current,
                        permissions_reviewed_at: Time.current, halon_answered_at: Time.current, slack_skipped_at: Time.current)
    sign_in(@owner.user, @workspace)

    get settings_workspace_path

    assert_response :success
    assert @onboarding.reload.checklist_completed_at
  end

  test "a provider sending the admin back from connecting is not turned around before it is heard" do
    sign_in(@owner.user, @workspace)

    get oauth_callback_integrations_path(state: "stale")

    assert_redirected_to integrations_path
    assert_equal "The connection attempt expired. Try again.", flash[:alert]
  end

  test "the chat Halon is met in stays open during setup and carries the guide" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    @onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current, permissions_reviewed_at: Time.current)
    sign_in(@owner.user, @workspace)

    get agent_chats_path, headers: inertia_headers

    assert_response :success
    guide = inertia_props[AgentChatsController::PROP_SETUP_GUIDE]
    assert_equal({ "question" => "What runs where in my stack?", "answered" => false, "setupPath" => onboarding_checklist_path }, guide)
  end

  test "a workspace that finished setup sees no guide in the chat" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    @onboarding.update!(checklist_completed_at: Time.current)
    sign_in(@owner.user, @workspace)

    get agent_chats_path, headers: inertia_headers

    assert_nil inertia_props[AgentChatsController::PROP_SETUP_GUIDE]
  end
end
