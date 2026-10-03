require "application_system_test_case"

class HalonPerformanceTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
  end

  test "a member opens Performance from the sidebar, reads the record, and narrows the window" do
    [ [ "confirmed", 3.days.ago ], [ "confirmed", 10.days.ago ], [ "partial", 12.days.ago ], [ nil, 2.days.ago ], [ "wrong", 1.day.ago ], [ "wrong", 20.days.ago ] ].each do |outcome, at|
      run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                              status: Investigation::STATUS_SUCCEEDED, created_at: at, started_at: at, completed_at: at + 4.minutes)
      run.create_finding!(summary: outcome == "wrong" ? "The deploy at 14:02 broke checkout" : "The disk on db-1 filled", outcome: outcome, outcome_at: (at + 1.hour if outcome))
    end
    Chat::Memory.learn!(@workspace, text: "A 5xx on checkout after a deploy has meant a full disk on db-1", subject: nil, source: @incident)

    visit dashboard_path
    click_link "Performance"

    assert_text "Nothing here is estimated."
    assert_text "5 of 6 answers rated"
    assert_text "A 5xx on checkout after a deploy has meant a full disk on db-1"
    page.save_screenshot(Rails.root.join("tmp/screenshots/halon-performance.png"))

    click_button "7 days"
    assert_text "2 of 3 answers rated"
  end

  test "a workspace Halon has not worked in yet says so" do
    visit halon_performance_path
    assert_text "Halon has not investigated anything in the last 30 days."
  end
end
