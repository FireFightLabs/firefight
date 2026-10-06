require "application_system_test_case"

class MemoryPageTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a member deletes a memory after the dialog says what goes, and deleting a rejected one says it may be learned again" do
    Chat::Memory.create!(workspace: @workspace, text: "Checkout retries twice", state: Chat::Memory::STATE_UNCONFIRMED)
    rejected = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen on Fridays", state: Chat::Memory::STATE_UNCONFIRMED)
    rejected.reject!(by: workspace_memberships(:alice_workspace_one), reason: "One off")

    visit memory_path
    within(:xpath, "//tr[.//p[text()='Checkout retries twice']]") { click_button "Actions" }
    find("[role=menuitem]", text: "Delete").click
    assert_text "\"Checkout retries twice\" is deleted for good. Halon stops using it, and nothing keeps where it came from."
    page.save_screenshot(Rails.root.join("tmp/screenshots/memory-delete-dialog.png"))
    within("[role=dialog]") { click_button "Delete" }

    assert_text "Deleted. Halon stops using it, and nothing keeps where it came from."
    assert_no_text "Checkout retries twice"

    click_button "Rejected"
    within(:xpath, "//tr[.//p[text()='Deploys happen on Fridays']]") { click_button "Actions" }
    find("[role=menuitem]", text: "Delete").click
    assert_text "Halon has nothing left to say the wording was wrong, so it may learn it again."
    within("[role=dialog]") { click_button "Delete" }
    assert_text "Deleted. Halon has nothing left to say the wording was wrong, so it may learn it again."
    assert_not Chat::Memory.exists?(rejected.id)
  end

  test "an admin sets how long unconfirmed memories last, and one nobody confirmed in time shows under Expired" do
    stale = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    stale.update_columns(updated_at: 40.days.ago)

    visit settings_workspace_path
    find("#memory-expiry").click
    find("[role=option]", text: "After 30 days without a confirmation").click
    page.save_screenshot(Rails.root.join("tmp/screenshots/memory-expiry-setting.png"))
    click_button "Save changes"
    assert_text "Workspace settings were updated."
    assert_equal 30, @workspace.reload.memory_expiry_days

    MemoryExpiryJob.perform_now
    visit memory_path
    assert_no_text "Deploys happen from main"
    click_button "Expired"
    assert_text "Deploys happen from main"
    assert_text "Nobody confirmed it within 30 days."
    page.save_screenshot(Rails.root.join("tmp/screenshots/memory-expired-filter.png"))
  end
end
