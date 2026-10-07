require "application_system_test_case"

class IncidentInvestigateButtonTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    @incident = incidents(:active_critical_ws1)
    sign_in(users(:bob), @workspace)
  end

  test "Investigate starts Halon, says so and opens the run, then points at it while it works" do
    visit incident_path(@incident)
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigate-button.png"))

    click_button "Investigate"

    assert_text "Halon is investigating #{@incident.identifier}."
    within("[role=dialog]") { assert_text "Reading what Firefight already knows." }
    started = @incident.investigations.sole
    assert_equal Investigation::TRIGGER_DASHBOARD, started.trigger_source
    assert_current_path incident_path(@incident, Investigation::QUERY_PARAM => started.id)
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigate-started.png"))

    find("[role=dialog] button", text: /close/i, visible: :all).click
    assert_no_selector "[role=dialog]"
    find("button[aria-label='Investigate'][aria-disabled='true']").hover
    assert_text "Halon is already investigating #{@incident.identifier}."
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigate-running.png"))

    click_link "Open the run"
    within("[role=dialog]") { assert_text "Reading what Firefight already knows." }
    assert_equal 1, @incident.investigations.count
  end

  test "a closed incident keeps the button and says why it cannot start" do
    visit incident_path(incidents(:resolved_minor_ws1))

    find("button[aria-label='Investigate'][aria-disabled='true']").hover

    assert_text incidents(:resolved_minor_ws1).investigation_blocked_reason
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigate-closed.png"))
  end

  test "on a phone the button keeps its icon beside the channel and the menu, and nothing scrolls sideways" do
    [ [ 390, 844 ], [ 320, 640 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      visit incident_path(@incident)

      assert_selector "button[aria-label='Investigate']"
      assert_no_sideways_scroll(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigate-#{width}.png"))
    end
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "a workspace without Halon shows no button" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    visit incident_path(@incident)

    assert_text @incident.name
    assert_no_button "Investigate"
  end

  private

  # Waits out a resize still settling under load before it decides.
  def assert_no_sideways_scroll(width)
    page.document.synchronize do
      next if evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

      raise Capybara::ExpectationNotMet, "the page scrolls sideways at #{width}"
    end
  end
end
