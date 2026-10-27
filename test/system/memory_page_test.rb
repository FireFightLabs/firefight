require "application_system_test_case"

class MemoryPageTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
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

  test "each memory says how it stands and what Halon's nightly check found, with its history a click away, and a person can still confirm it" do
    review = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.current, removal_cap: 3)
    checked = Chat::Memory.create!(workspace: @workspace, text: "web deploys from main", state: Chat::Memory::STATE_UNCONFIRMED)
    checked.record!(Chat::MemoryEvent::KIND_LEARNED, actor: Chat::MemoryEvent::ACTOR_HALON)
    checked.verified_by_halon!(evidence: "The deploy settings of web name main.", review: review)
    tried = Chat::Memory.create!(workspace: @workspace, text: "Checkout runs in Frankfurt", state: Chat::Memory::STATE_UNCONFIRMED)
    tried.contradicted!(Chat::Memory.create!(workspace: @workspace, text: "Checkout runs in Dublin", state: Chat::Memory::STATE_UNCONFIRMED),
                        reason: "A chat showed \"Checkout runs in Dublin\".")
    tried.unsettled_by_halon!(note: "Nothing Halon reads says where Checkout runs.")
    held = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries twice", state: Chat::Memory::STATE_UNCONFIRMED)
    held.update_columns(checked_at: Time.current, check_outcome: Chat::Memory::OUTCOME_HELD)

    visit memory_path
    assert_text "Checked by Halon"
    assert_text "Halon checked it against production on #{Time.current.strftime('%b %-d, %Y')}. The deploy settings of web name main."
    within(:xpath, "//tr[.//p[text()='web deploys from main']]") { click_button "Show history" }
    assert_text "Halon added it"
    assert_text "Halon checked it against production and it held"
    page.save_screenshot(Rails.root.join("tmp/screenshots/memory-checked-by-halon.png"))

    find("[role=tab]", text: "Memories").assert_text("1")
    assert_text "Halon reviews them against production in a nightly check, a batch at a time"
    assert_text "Halon found evidence against it on #{Time.current.strftime('%b %-d, %Y')}, but left it as it was for now."
    click_button "Disputed"
    assert_text "Halon could not settle this against production, so it waits on a person."
    page.save_screenshot(Rails.root.join("tmp/screenshots/memory-waits-on-a-person.png"))

    click_button "In use"
    within(:xpath, "//tr[.//p[text()='web deploys from main']]") { click_button "Confirm" }
    assert_text "Confirmed. Halon now reads it as confirmed by you."
    assert_text "Confirmed by #{workspace_memberships(:alice_workspace_one).display_name}"
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
