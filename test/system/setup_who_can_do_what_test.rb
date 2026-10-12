require "application_system_test_case"

# The Who can do what step of setup: a row per connection, each dropdown saved at once with a toast, and the same grants
# the Permissions screen edits.
class SetupWhoCanDoWhatTest < ApplicationSystemTestCase
  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    Integrations::ConnectionRefresh.stubs(:run!)
    @owner = Workspace.sign_up!(name: "Rows Co", user: User.create!(email: "rows-#{SecureRandom.hex(3)}@example.com", name: "Rae Rows"))
    @workspace = @owner.workspace
    @workspace.onboarding.update!(ai_choice: WorkspaceOnboarding::AI_HOUSE, ai_chosen_at: Time.current, stack_done_at: Time.current)
  end

  test "an admin takes reads away, lets everyone change one tool and picks who changes another, each with a toast" do
    ana = member("Ana Ruiz")
    member("Ben Okafor")
    production = connection("Production")
    staging = connection("Staging")
    sign_in(@owner.user, @workspace)

    visit onboarding_checklist_path

    assert_selector "h1", text: "Who can do what"
    assert_text "Choose what people in your workspace can ask Halon to look at or change in each tool. Admins can always do everything."
    assert_text "Changes always follow your approval rules."
    assert_no_text "these choices apply to people you invite later"

    pick "Members can read Production (Northflank)", "Nobody"
    assert_text "Members can no longer read Production (Northflank)."
    assert_not pack(production, Ability::Role::PACK_READ).every_member?

    pick "Members can change Staging (Northflank)", "Everyone"
    assert_text "Members can change Staging (Northflank)."
    assert pack(staging, Ability::Role::PACK_CHANGES).every_member?

    pick "Members can change Production (Northflank)", "Choose people…"
    within("[role=dialog]") do
      assert_text "Who can change Production (Northflank)?"
      click_button "Pick people"
    end
    page.document.find("[cmdk-item]", text: "Ana Ruiz").click
    page.document.find("[cmdk-item]", text: "Ben Okafor").click
    page.document.find("[cmdk-input]").send_keys(:escape)
    within("[role=dialog]", text: "Who can change") { click_button "Save" }

    assert_text "Ana Ruiz and Ben Okafor can change Production (Northflank)."
    assert_selector "button[aria-label='Members can change Production (Northflank)']", text: "2 people"
    assert_equal 2, pack(production, Ability::Role::PACK_CHANGES).grants.count

    Ability::Grant.withhold!(workspace: @workspace, principal: ana, role: pack(staging, Ability::Role::PACK_READ))
    visit onboarding_checklist_path
    assert_text "Except 1 person"

    click_button "Continue"
    assert_text "Permissions are set."
    assert pack(staging, Ability::Role::PACK_CHANGES).every_member?
  end

  test "a workspace of one says the choices are for people invited later, and keeps the rows usable" do
    connection("Production")
    connection("Staging")
    sign_in(@owner.user, @workspace)

    visit onboarding_checklist_path

    assert_text "You are the only one here so far, so these choices apply to people you invite later."
    pick "Members can change Staging (Northflank)", "Everyone"
    assert_text "Members can change Staging (Northflank)."
  end

  test "with nothing connected the step says so and links back to connecting" do
    sign_in(@owner.user, @workspace)

    visit onboarding_checklist_path

    assert_text "Nothing is connected yet, so there is nothing to choose."
    click_link "Go back to Connect your stack"
    assert_selector "h1", text: "Connect your stack"
  end

  private

  def member(name)
    user = User.create!(email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com", name: name)
    @workspace.workspace_memberships.create!(user: user, role: :member, joined_at: Time.current)
  end

  def connection(name)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: name)
    integration.tools.create!(name: "list_services", read_only: true, enabled: true)
    integration.tools.create!(name: "restart_service", read_only: false, enabled: true)
    integration
  end

  def pack(integration, kind) = integration.permission_packs.find_by!(pack: kind)

  def pick(label, choice)
    find("button[aria-label='#{label}']").click
    find("[role=option]", text: choice, exact_text: true).click
  end
end
