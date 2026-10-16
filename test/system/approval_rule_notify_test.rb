require "application_system_test_case"

# Where an approval rule asks starts on Default, which asks a Halon chat's request in the chat's thread and of its
# approvers directly. The incidents channel is a choice an admin makes.
class ApprovalRuleNotifyTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a new rule starts on Default, saves it with a toast, and the incidents channel is a choice" do
    visit gateway_permissions_path
    click_button "Rules"
    click_button "Add rule"

    within("[role=dialog]") { assert_text "Default (the chat's thread and approvers' DMs)" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/approval_rule_default.png").to_s)
    click_button "Create rule"

    assert_text "Approval rule was created."
    assert_equal PolicyRule::ApprovalOutcome::NOTIFY_DEFAULT, @workspace.approval_rules.sole.outcome.dig("require", "notify")

    click_button "Actions"
    find("[role=menuitem]", text: "Edit").click
    within("[role=dialog]") { find("[role=combobox]", text: "Default (the chat's thread and approvers' DMs)").click }
    find("[role=option]", text: "Incidents channel").click
    click_button "Save rule"

    assert_text "Approval rule was updated."
    assert_equal PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL, @workspace.approval_rules.sole.reload.outcome.dig("require", "notify")
  end
end
