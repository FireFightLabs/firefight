require "test_helper"

class WorkspaceOnboarding::ChecklistTest < ActiveSupport::TestCase
  include AiAccountTestHelper

  setup do
    @owner = Workspace.sign_up!(name: "Checklist Co", user: User.create!(email: "owner-#{SecureRandom.hex(4)}@example.com", name: "Olive Owner"))
    @workspace = @owner.workspace
    @onboarding = @workspace.onboarding
  end

  test "a new workspace starts on choosing Halon's AI, with the account already done" do
    steps = @onboarding.steps

    assert_equal WorkspaceOnboarding::CHECKLIST_STEPS, steps.map(&:key)
    assert_equal WorkspaceOnboarding::STATE_DONE, steps.first.state
    assert_equal WorkspaceOnboarding::STEP_AI, @onboarding.current_step.key
    later = steps.drop(2).reject { |step| step.key == WorkspaceOnboarding::STEP_HALON }
    assert(later.all? { |step| step.state == WorkspaceOnboarding::STATE_WAITING })
    assert_equal WorkspaceOnboarding::NOT_YET, steps.find { |step| step.key == WorkspaceOnboarding::STEP_STACK }.note
  end

  test "the test incident waits on Slack and says so" do
    step = @onboarding.steps.find { |candidate| candidate.key == WorkspaceOnboarding::STEP_TEST_INCIDENT }

    assert_equal WorkspaceOnboarding::STATE_WAITING, step.state
    assert_equal @workspace.incidents_blocked_reason, step.note
  end

  test "only someone who may change the workspace is steered to setup" do
    member = @workspace.workspace_memberships.create!(user: User.create!(email: "m-#{SecureRandom.hex(4)}@example.com", name: "Mo Member"), role: :member, joined_at: Time.current)

    assert @onboarding.steers?(@owner)
    assert_not @onboarding.steers?(member)

    @onboarding.update!(checklist_completed_at: Time.current)
    assert_not @onboarding.steers?(@owner)
  end

  test "an own AI account counts only once its check has passed" do
    assert_equal WorkspaceOnboarding::NO_WORKING_ACCOUNT, @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_ACCOUNT)

    account = add_ai_account
    assert_equal WorkspaceOnboarding::NO_WORKING_ACCOUNT, @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_ACCOUNT)

    account.checked!
    assert_nil @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_ACCOUNT)
  end

  test "credits are offered only where Firefight sells them" do
    assert_not_includes @onboarding.ai_choices, WorkspaceOnboarding::AI_CREDITS
    assert_equal WorkspaceOnboarding::NO_CREDITS, @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_CREDITS)

    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(true, false))
    assert_includes @onboarding.ai_choices, WorkspaceOnboarding::AI_CREDITS
    assert_nil @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_CREDITS)
  end

  test "an install someone runs offers the AI keys it runs on" do
    assert_includes @onboarding.ai_choices, WorkspaceOnboarding::AI_HOUSE
    assert_nil @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_HOUSE)
  end

  test "a hosted workspace with no keys of Firefight's own is not offered them" do
    on_firefights_cloud!

    assert_equal [ WorkspaceOnboarding::AI_ACCOUNT ], @onboarding.ai_choices
    assert_equal WorkspaceOnboarding::NO_HOUSE, @onboarding.ai_choice_blocked_reason(WorkspaceOnboarding::AI_HOUSE)
  end

  test "a required category cannot be skipped and needs a working connection" do
    code = card("code")

    assert code.category.required
    assert_equal WorkspaceOnboarding::CATEGORY_REQUIRED, WorkspaceOnboarding.category_answer_blocked_reason(code, WorkspaceOnboarding::ANSWER_UNUSED)
    assert_equal WorkspaceOnboarding::NOTHING_CONNECTED, WorkspaceOnboarding.category_answer_blocked_reason(code, WorkspaceOnboarding::ANSWER_CONNECTED)

    integration = connect("github", "GitHub")
    integration.integration_environments.create!(enabled: true, health_status: IntegrationEnvironment::HEALTH_FAILING)
    assert_equal WorkspaceOnboarding::CHECK_FAILING, WorkspaceOnboarding.category_answer_blocked_reason(card("code"), WorkspaceOnboarding::ANSWER_CONNECTED)

    connect("gitlab", "GitLab")
    assert_nil WorkspaceOnboarding.category_answer_blocked_reason(card("code"), WorkspaceOnboarding::ANSWER_CONNECTED)
  end

  test "a category Halon can do without may be answered with we don't use this" do
    issues = card("issues")

    assert_not issues.category.required
    assert_nil WorkspaceOnboarding.category_answer_blocked_reason(issues, WorkspaceOnboarding::ANSWER_UNUSED)
  end

  test "the stack is done once every category has an answer" do
    categories = IntegrationProvider.category_list
    categories.first(categories.size - 1).each { |category| @onboarding.answer_category!(category, WorkspaceOnboarding::ANSWER_UNUSED) }
    assert_nil @onboarding.stack_done_at

    @onboarding.answer_category!(categories.last, WorkspaceOnboarding::ANSWER_UNUSED)
    assert @onboarding.stack_done_at
    assert_equal categories.map(&:slug).sort, @onboarding.stack_answers.keys.sort
  end

  test "answers from two places are both kept" do
    other = WorkspaceOnboarding.find(@onboarding.id)
    code = IntegrationProvider.category_for!("code")
    issues = IntegrationProvider.category_for!("issues")

    @onboarding.answer_category!(code, WorkspaceOnboarding::ANSWER_CONNECTED)
    other.answer_category!(issues, WorkspaceOnboarding::ANSWER_UNUSED)

    assert_equal({ code.slug => WorkspaceOnboarding::ANSWER_CONNECTED, issues.slug => WorkspaceOnboarding::ANSWER_UNUSED }, @onboarding.reload.stack_answers)
  end

  test "the first question names what runs the stack" do
    connect("northflank", "Northflank")
    @onboarding.answer_category!(card("cloud_and_hosting").category, WorkspaceOnboarding::ANSWER_CONNECTED)

    assert_equal "What runs where in my stack across Northflank?", @onboarding.first_question
  end

  test "Halon that cannot run here does not hold setup up" do
    step = @onboarding.steps.find { |candidate| candidate.key == WorkspaceOnboarding::STEP_HALON }

    assert_equal WorkspaceOnboarding::STATE_UNAVAILABLE, step.state
    assert_equal Investigation.unavailable_reason(@workspace), step.note
  end

  test "Halon's answer in an admin's own chat finishes Meet Halon, and a member's does not" do
    member = @workspace.workspace_memberships.create!(user: User.create!(email: "q-#{SecureRandom.hex(4)}@example.com", name: "Quinn"), role: :member, joined_at: Time.current)

    @onboarding.halon_answered!(Conversation.start_personal!(workspace: @workspace, member: member))
    assert_nil @onboarding.reload.halon_answered_at

    @onboarding.halon_answered!(Conversation.start_personal!(workspace: @workspace, member: @owner))
    assert @onboarding.reload.halon_answered_at
  end

  test "skipping Slack finishes setup without a test incident" do
    finish_through_halon!
    assert_equal WorkspaceOnboarding::STEP_SLACK, @onboarding.current_step.key
    assert_not @onboarding.finish_if_done!

    @onboarding.skip_slack!
    steps = @onboarding.steps
    assert_equal WorkspaceOnboarding::STATE_SKIPPED, steps.find { |step| step.key == WorkspaceOnboarding::STEP_SLACK }.state
    assert_equal WorkspaceOnboarding::STATE_SKIPPED, steps.find { |step| step.key == WorkspaceOnboarding::STEP_TEST_INCIDENT }.state

    assert @onboarding.finish_if_done!
    assert @onboarding.checklist_completed_at
    assert_not @onboarding.finish_if_done!, "only the first request to see it done finishes it"
  end

  test "with Slack connected the test incident is the last step" do
    finish_through_halon!
    @workspace.update!(platform: Platforms::SLACK, platform_id: "T#{SecureRandom.hex(6)}", access_token: "xoxb-test", installed_at: Time.current)

    assert_equal WorkspaceOnboarding::STEP_TEST_INCIDENT, @onboarding.reload.current_step.key
    assert_not @onboarding.done?

    @workspace.incidents.create!(declared_by: @owner, incident_status: @workspace.incident_statuses.default_status,
                                 incident_severity: @workspace.incident_severities.first!, name: "First one", is_private: false, is_test: true,
                                 declared_at: Time.current, source: Incident::SOURCE_DASHBOARD)
    assert @onboarding.done?
  end

  private

  def add_ai_account
    add_ai_account!(@workspace, provider: "anthropic", key: "sk-ant-setup")
  end

  def connect(provider, name)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name)
  end

  def card(slug)
    IntegrationProvider.card_for(@workspace, IntegrationProvider.category_for!(slug))
  end

  def finish_through_halon!
    @onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current, permissions_reviewed_at: Time.current)
  end
end
