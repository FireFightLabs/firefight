require "application_system_test_case"

# A team writes its Friday freeze on the Freeze windows page. The page reads it back as a sentence, and a plan for
# Saturday is refused with it.
class HandbookFreezeWindowsTest < ApplicationSystemTestCase
  SHOTS = ENV["HANDBOOK_SHOTS"].presence

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a member starts the Freeze windows page, sets a weekly window, and the page and plans read it" do
    visit settings_handbook_path
    find("h3", text: "Freeze windows", exact_text: true).ancestor("div.rounded-lg").click_button("Write this page")

    assert_selector "h3#handbook-freeze-windows"
    fill_in "Name", with: "Friday afternoons"
    choose_time_zone "Europe/Berlin"
    fill_in "Who may lift it", with: "the CTO"
    save_shot("23-freeze-windows-editor")
    click_button "Save page"

    assert_text "Freeze windows was added. Halon follows it from its next chat or investigation."
    assert_text "Changes are frozen every Friday from 15:00 to Monday 08:00 (Europe/Berlin), for Friday afternoons. The CTO may lift it."
    save_shot("24-freeze-windows-page")

    saturday = ActiveSupport::TimeZone["Europe/Berlin"].now.next_occurring(:saturday).change(hour: 12)
    assert Workspace::FreezeWindows.covering(@workspace, saturday)
  end

  private

  def choose_time_zone(zone)
    find("#" + find(:label, text: "Time zone")[:for]).click
    find("[cmdk-input]").set(zone)
    find("[cmdk-item]", text: zone.tr("_", " "), match: :first).click
  end

  def save_shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end
end
