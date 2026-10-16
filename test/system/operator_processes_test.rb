require "application_system_test_case"

class OperatorProcessesTest < ApplicationSystemTestCase
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    sign_in(@operator, workspaces(:slack_workspace_one))
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
    @incident = incidents(:active_critical_ws1)
    @workflow = SolidWorkflow::Workflow.create!(
      name: "incident.creation.v1", workflow_class: "IncidentCreationWorkflow", subject: @incident, state: "failed", created_at: 5.minutes.ago
    )
    { "create_slack_channel" => [ [], "succeeded" ], "set_channel_metadata" => [ %w[create_slack_channel], "succeeded" ],
      "post_announcement" => [ %w[create_slack_channel], "succeeded" ], "invite_responders" => [ %w[create_slack_channel], "failed" ],
      "post_quick_actions_message" => [ %w[set_channel_metadata], "succeeded" ], "attach_runbooks" => [ %w[post_quick_actions_message], "cancelled" ] }
      .each_with_index do |(name, (deps, status)), index|
        @workflow.steps.create!(
          name: name, position: index, depends_on: deps, status: status, attempts: status == "failed" ? 3 : 1, max_attempts: 3,
          started_at: (5 - index).minutes.ago, completed_at: (5 - index).minutes.ago + 1.second,
          last_error: ("AdapterError::NotInChannel: not_in_channel" if status == "failed")
        )
      end
    @workflow.record_event(SolidWorkflow::Events::Workflow::STARTED)
    @workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: @workflow.steps.find_by!(name: "invite_responders"), error: "not_in_channel", attempt: 3)
    PlatformCallFailure.create!(workspace: @incident.workspace, platform: Platforms::SLACK, operation: "conversations.invite",
                                error_class: "AdapterError::NotInChannel", message: "Slack API error: not_in_channel", channel_id: @incident.channel_id)
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator follows a failed incident to its workflow and sees what failed and why" do
    visit operator_incidents_path
    assert_text @incident.identifier
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-incidents.png"))

    find("a[href=\"#{operator_incident_path(@incident)}\"]").click
    assert_text "invite_responders"
    # The fixtures' failed webhook delivery sits on the same timeline at the time the fixtures loaded, which falls
    # among these steps when the suite has run for a few minutes, so the step's own row is opened.
    within(find("li", text: "invite_responders")) do
      click_button "Show the error"
      assert_text "not_in_channel"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-incident.png"))

    visit operator_workflow_path(@workflow)
    assert_text(/selected step/i)
    assert_selector "button[aria-pressed=true]", text: "invite_responders"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-workflow.png"))
  end

  test "an operator sees why a Slack call failed and opens every time it failed that way" do
    workspace = @incident.workspace
    message = 'Slack API error: invalid_arguments (details: {"error":"invalid_arguments","response_metadata":{"messages":' \
              '["[ERROR] missing required field: channel","[ERROR] missing required field: message_ts"],"warnings":["missing_charset"]}})'
    failures = [ 40, 20, 5 ].map do |minutes|
      PlatformCallFailure.create!(workspace: workspace, platform: Platforms::SLACK, operation: "chat.getPermalink", error_class: "AdapterError",
                                  message: message, channel_id: @incident.channel_id, created_at: minutes.minutes.ago)
    end
    PlatformCallFailure.create!(workspace: workspace, platform: Platforms::SLACK, operation: "agents.sessions.setStatus", error_class: "AdapterError",
                                message: 'Slack API error: not_authorized (details: {"error":"not_authorized","response_metadata":{"warnings":["missing_charset"]}})')

    visit operator_root_path
    assert_text "3 times · invalid_arguments: missing required field: channel, missing required field: message_ts"
    assert_text "1 time · not_authorized"
    assert_no_text "missing_charset"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-overview-platform-failures.png"))

    find("a[href=\"#{operator_platform_failure_path(failures.last)}\"]").click
    assert_text "Why Slack refused it"
    assert_text "missing required field: message_ts"
    assert_selector "pre", text: "missing_charset", count: 3
    assert_link @incident.identifier, count: 3
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-platform-failure.png"))
  end
end
