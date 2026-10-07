require "application_system_test_case"

class SetupChecklistTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include AiAccountTestHelper

  PHONE = [ 390, 844 ].freeze

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    Integrations::ConnectionRefresh.stubs(:run!)
  end

  test "someone new reads the letter, then sets up AI, their stack, permissions and Halon, and leaves Slack for later" do
    FirefightAi.stubs(:check_account).returns(true)
    token = LoginToken.issue!(email: "nova@example.com")
    visit email_sign_in_link_path(token: token)
    click_on "Sign in"
    fill_in "Your name", with: "Nova Quinn"
    fill_in "Workspace name", with: "Nova Labs"
    click_on "Create workspace"

    assert_text "You're in"
    screenshot("letter")
    click_on "Continue to Nova Labs"

    assert_text "Choose Halon's AI"
    assert_text "1 of 7 done"
    screenshot("ai")
    phone_screenshot("ai")

    workspace = Workspace.find_by!(name: "Nova Labs")
    onboarding = workspace.onboarding

    find("label", text: "Use my own AI account").click
    click_button "Add account"
    within("[role=dialog]") do
      fill_in "Name", with: "Team Anthropic"
      fill_in "API key", with: "sk-ant-team-key-4f2a"
      choose_model "Main model", "claude-sonnet-4-5"
      choose_model "Quick model", "claude-haiku-4-5"
      click_button "Add and check"
    end
    assert_text "Team Anthropic was added and works."
    assert_text "Choose Halon's AI"
    screenshot("ai-account-added")
    click_button "Continue"

    assert_text "Halon will use your own AI account."
    assert_text "Connect your stack"
    assert_text "0 of #{IntegrationProvider.category_list.size} answered"
    within("section[aria-label='Cloud and hosting']") do
      assert_text "Required"
      assert_text "Halon needs one of these to investigate, so connect at least one."
      assert_no_button "We don't use this"
      assert_button "Continue", disabled: true
    end
    screenshot("stack-required")
    phone_screenshot("stack-required")

    # Hosts connect with a token the provider checks, which happens out of this test, so the connection is made here.
    workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    visit onboarding_checklist_path
    within("section[aria-label='Cloud and hosting']") do
      assert_text "Northflank"
      assert_text "Connected"
      click_button "Continue"
    end
    assert_text "Cloud and hosting is set."

    within("section[aria-label='Observability']") do
      within("li", text: "Grafana") { click_button "Connect" }
    end
    within("[role=dialog]") do
      assert_text "Connect Grafana"
      fill_in "connect-url", with: "https://grafana.example.com/mcp"
      screenshot("stack-connect-dialog")
      click_button "Connect & discover tools"
    end
    assert_text "Grafana is connected."
    within("section[aria-label='Observability']") do
      assert_text "Connected"
      assert_button "Connect another"
      click_button "Continue"
    end
    assert_text "Observability is set."

    within("section[aria-label='Alerting and on-call']") { click_button "We don't use this" }
    assert_text "Alerting and on-call skipped."
    screenshot("stack-skipped")

    workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    answer_rest_of_stack(onboarding, except: "code")
    visit onboarding_checklist_path
    within("section[aria-label='Code']") { click_button "Continue" }

    assert_text "Code is set."
    assert_text "Who can do what"
    assert_text "Everyone reads every connected tool. Changes need a pack."
    screenshot("permissions")
    phone_screenshot("permissions")
    Investigation.stubs(:unavailable_reason).returns(nil)
    click_button "Continue"

    assert_text "Permissions are set."
    assert_selector "h1", text: "Meet Halon"
    assert_text "What runs where in my stack across Northflank?"
    screenshot("halon")
    click_link "Ask Halon"

    assert_text "Meet Halon."
    assert_equal "What runs where in my stack across Northflank?", find("textarea").value
    screenshot("halon-chat")
    phone_screenshot("halon-chat")

    conversation = Conversation.start_personal!(workspace: workspace, member: workspace.workspace_memberships.sole)
    conversation.ask!("What runs where in my stack across Northflank?")
    conversation.note!("Two services run on Northflank, api and worker, both in the production project.")
    conversation.reply_delivered!
    onboarding.halon_answered!(conversation)
    visit agent_chat_path(conversation)
    assert_text "Halon answered your first question"
    screenshot("halon-answered")
    click_link "Back to setup"

    assert_text "Connect Slack"
    screenshot("slack")
    phone_screenshot("slack")
    click_button "Not now"

    assert_text "Setup is done. Welcome to Firefight."
    assert_text "Connect Slack to run incidents"
    declare = find_button("Declare incident", disabled: true)
    declare.find(:xpath, "..").hover
    assert_text "Connect Slack first to run incidents."
    screenshot("done")
    phone_screenshot("done")
    assert onboarding.reload.checklist_completed_at
  end

  test "setup picks up where it was left, on the next category to answer" do
    owner = signed_up_owner
    onboarding = owner.workspace.onboarding
    onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current)
    first, second = IntegrationProvider.category_list.first(2)
    owner.workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    onboarding.answer_category!(first, WorkspaceOnboarding::ANSWER_CONNECTED)
    sign_in(owner.user, owner.workspace)

    visit settings_members_path

    assert_text "Connect your stack"
    assert_text "2 of 7 done"
    assert_text "1 of #{IntegrationProvider.category_list.size} answered"
    assert_selector "section[aria-label='#{second.name}']"
    screenshot("resume")

    find("button", text: first.name).click
    within("section[aria-label='#{first.name}']") { assert_text "Northflank" }
    find("nav[aria-label='Setup steps'] button", text: "Choose Halon's AI").click
    assert_selector "h1", text: "Choose Halon's AI"
    assert_button "Save"
  end

  test "on Firefight's cloud, Firefight credits are the other choice, once there is a balance to spend" do
    credit = AiAccountTestHelper::Credit.new(false, false)
    on_firefights_cloud!(credit: credit)
    owner = signed_up_owner
    sign_in(owner.user, owner.workspace)

    visit onboarding_checklist_path
    assert_no_text "Use the AI keys this Firefight runs on"
    find("label", text: "Use Firefight credits").click

    assert_text "$12.40 left"
    assert_link "Buy credits", href: "/app/settings/billing#credits"
    assert_no_button "Add account"
    find("button", text: "Continue").find(:xpath, "..").hover
    assert_text "Buy Firefight credits first."
    screenshot("ai-credits")
    phone_screenshot("ai-credits")

    credit.spendable = true
    visit onboarding_checklist_path
    find("label", text: "Use Firefight credits").click
    click_button "Continue"

    assert_text "Halon will use your Firefight credits."
    assert_selector "h1", text: "Connect your stack"
    assert_equal WorkspaceOnboarding::AI_CREDITS, owner.workspace.onboarding.reload.ai_choice
  end

  test "a category Halon can do without is answered with we don't use this, and a required one cannot be" do
    owner = signed_up_owner
    onboarding = owner.workspace.onboarding
    onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current)
    sign_in(owner.user, owner.workspace)

    visit onboarding_checklist_path
    find("button", text: "Product analytics").click
    within("section[aria-label='Product analytics']") { click_button "We don't use this" }

    assert_text "Product analytics skipped."
    assert_equal WorkspaceOnboarding::ANSWER_UNUSED, onboarding.reload.stack_answers["product_analytics"]

    find("button", text: "Product analytics").click
    within("section[aria-label='Product analytics']") { assert_text "Not used" }

    find("button", text: "Code", exact_text: true).click
    within("section[aria-label='Code']") do
      assert_no_button "We don't use this"
      find("button", text: "Continue").find(:xpath, "..").hover
    end
    assert_text "Connect one of these first."
    screenshot("required-category")
  end

  test "with Slack connected, the test incident is the last step and declaring it opens the incident" do
    stub_successful_slack_workflow
    owner = signed_up_owner
    workspace = owner.workspace
    workspace.update!(platform: Platforms::SLACK, platform_id: "T#{SecureRandom.hex(5)}", access_token: "xoxb-test", installed_at: Time.current,
                      incidents_channel_id: "C_INCIDENTS")
    workspace.onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current,
                                 permissions_reviewed_at: Time.current, halon_answered_at: Time.current)
    sign_in(owner.user, workspace)

    visit onboarding_checklist_path

    assert_selector "h1", text: "Run a test incident"
    assert_text "Declare an incident."
    screenshot("test-incident")
    click_button "Declare a test incident"
    within("[role=dialog]") do
      assert_text "A test incident works like a real one and is not counted in your metrics."
      find("input[placeholder='Write something']").fill_in(with: "Trying Firefight")
      click_button "Select severity"
    end
    page.document.find("[cmdk-item]", text: workspace.incident_severities.order(:position).first.name, exact_text: true).click
    within("[role=dialog]") { click_button "Declare" }

    assert_text "Trying Firefight"
    assert workspace.onboarding.reload.checklist_completed_at
  end

  test "the test incident waits for Slack and says why" do
    owner = signed_up_owner
    owner.workspace.onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current)
    sign_in(owner.user, owner.workspace)

    visit onboarding_checklist_path

    assert_selector "nav[aria-label='Setup steps'] button[disabled]", text: "Run a test incident"
    assert_selector "nav[aria-label='Setup steps'] button[disabled]", text: "Connect Slack"
  end

  test "someone who joins while an admin is still setting up goes to the dashboard and never sees setup" do
    owner = signed_up_owner
    member = owner.workspace.workspace_memberships.create!(user: User.create!(email: "mid-#{SecureRandom.hex(3)}@example.com", name: "Mira Member"),
                                                           role: :member, joined_at: Time.current)
    sign_in(member.user, owner.workspace)

    visit dashboard_path
    assert_no_text "Choose Halon's AI"
    assert_text "Connect Slack to run incidents"

    visit onboarding_checklist_path
    assert_current_path dashboard_path
    assert_no_selector "nav[aria-label='Setup steps']"
    screenshot("member")
    phone_screenshot("member")
  end

  test "Meet Halon waits, and says why, while Halon cannot answer yet" do
    owner = signed_up_owner
    owner.workspace.onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current,
                                       permissions_reviewed_at: Time.current)
    Investigation.stubs(:unavailable_reason).returns("The AI model is not fully set up yet. An admin needs to finish setting it up.")
    sign_in(owner.user, owner.workspace)

    visit onboarding_checklist_path

    assert_selector "h1", text: "Meet Halon"
    assert_text "The AI model is not fully set up yet. An admin needs to finish setting it up. Change it under Choose Halon's AI."
    assert_button "Ask Halon", disabled: true
    assert_selector "nav[aria-label='Setup steps'] button[disabled]", text: "Connect Slack"
    screenshot("halon-held")
  end

  private

  def signed_up_owner
    Workspace.sign_up!(name: "Resume Co", user: User.create!(email: "resume-#{SecureRandom.hex(3)}@example.com", name: "Rae Resume"))
  end

  def answer_rest_of_stack(onboarding, except:)
    IntegrationProvider.category_list.each do |category|
      next if category.slug == except || onboarding.reload.stack_answers.key?(category.slug)

      onboarding.answer_category!(category, WorkspaceOnboarding::ANSWER_UNUSED) unless category.required
    end
  end

  def choose_model(label, model)
    find("label", text: label, exact_text: true).find(:xpath, "..").find("button[role=combobox]").click
    page.document.find("[cmdk-item]", text: model, exact_text: true).click
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/setup-#{name}.png").to_s)
  end

  def phone_screenshot(name)
    page.current_window.resize_to(*PHONE)
    screenshot("#{name}-phone")
    page.current_window.resize_to(*SCREEN_SIZE)
  end
end
