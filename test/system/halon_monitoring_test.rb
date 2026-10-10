require "application_system_test_case"

class HalonMonitoringTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    Investigation.stubs(:start_refusal).returns(nil)
    sign_in(users(:alice), @workspace)
  end

  test "a check is added from the dialog, says so, and shows with its schedule" do
    visit halon_monitoring_path
    assert_text "No scheduled checks yet"

    click_button "Add check"
    fill_in "Name", with: "Disks every morning"
    click_button "Create check"

    assert_text "Disks every morning was created."
    assert_text "Disk space"
    assert_text "Every day at 09:00"
    assert @workspace.investigation_checks.exists?(name: "Disks every morning")
  end

  test "what Halon raised shows its urgency, its date and why it is still waiting" do
    reading = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "orders-db volume",
                                                 summary: "The orders-db volume is full around Oct 28.", severity: Investigation::Notice::SEVERITY_MEDIUM,
                                                 due_on: Date.new(2026, 10, 28))
    Investigation::Notice.observe!(@workspace, reading).unsaid_because!(Investigation::Notice::NO_CHANNEL)

    visit halon_monitoring_path

    assert_text "Disk space: orders-db volume"
    assert_text "Needs doing within weeks"
    assert_text "Oct 28, 2026"
    assert_text "No team channel or monitoring channel to say it in"
  end

  test "turning the leaked secrets switch off says so" do
    visit halon_monitoring_path

    find("#security-events").click

    assert_text "Halon no longer looks into leaked secrets."
    assert_not @workspace.reload.halon_security_events_enabled
  end
end
