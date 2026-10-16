require "application_system_test_case"

class IncidentLiveUpdatesTest < ApplicationSystemTestCase
  # Counts the reads the live connection asks for, which are partial reloads of the page's own address.
  LIVE_READS = <<~JS.freeze
    window.liveReads = 0;
    const openRequest = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      if (String(method).toLowerCase() === "get" && String(url).includes(window.location.pathname)) { window.liveReads += 1; }
      return openRequest.call(this, method, url, ...rest);
    };
  JS

  # The test adapter only records broadcasts, and this test needs the browser to receive them.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart

    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:manual_incident_ws1)
    @incident.update_columns(channel_id: "C0LIVE01", channel_name: "inc-005-monitoring-alert")
    stub_successful_slack_workflow
    sign_in(users(:alice), @workspace)
    # The sign in helper stubs the controller, not the session the socket reads, so the socket is stubbed too.
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "a change made in Slack shows on the open page in place, and what is being typed there stays" do
    visit incident_path(@incident)
    assert_text @incident.name
    open_live_connection
    watch_page

    actions = find("section", text: "Actions · None yet")
    actions.find("button[aria-label='Add action item']").click
    within("[role=dialog]") { fill_in "Description", with: "Write the customer note" }

    slack_member = workspace_memberships(:bob_workspace_one)
    IncidentLifecycleService.new(@workspace).assign_lead(@incident, workspace_memberships(:alice_workspace_one), changed_by: slack_member)
    IncidentActionService.new(@workspace).create_action(
      incident: @incident, created_by: slack_member, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Check the replica lag"
    )

    assert_text "Check the replica lag"
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-live-dialog-kept.png"))
    within("[role=dialog]") do
      assert_equal "Write the customer note", find_field("Description").value
      click_button "Cancel"
    end

    within(lead_cell) { assert_text "Alice Smith" }
    assert_text "assigned the lead to"
    assert page.evaluate_script("window.stillTheSamePage"), "the page was visited whole instead of reading the change in place"
    assert_no_selector "[data-sonner-toast]"
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-live-lead.png"))
  end

  test "a change made on the page toasts once, though the page also hears about it" do
    visit incident_path(@incident)
    assert_text @incident.name
    open_live_connection
    page.execute_script(LIVE_READS)

    find("section", text: "Actions · None yet").find("button[aria-label='Add action item']").click
    within("[role=dialog]") do
      fill_in "Description", with: "Roll back the deploy"
      click_button "Create"
    end

    assert_toast "The action item was added."
    page.document.synchronize(10) { raise Capybara::ElementNotFound, "the live reload never came" if page.evaluate_script("window.liveReads").zero? }
    assert_selector "[data-sonner-toast]", count: 1
    assert_text "Roll back the deploy"
  end

  private

  # A change that skips callbacks says nothing, so signalling it by hand until it shows proves the socket is open before
  # the real change is made.
  def open_live_connection
    @incident.update_column(:summary, "Customers see a spinner at checkout")
    50.times do
      IncidentChannel.changed(@incident.id, Incident::LiveSignal::PART_INCIDENT)
      return if page.has_text?("Customers see a spinner at checkout", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end

  def lead_cell
    find(:xpath, "//div[normalize-space(text())='Lead']/following-sibling::div")
  end
end
