require "application_system_test_case"

class OperatorProcessesTest < ApplicationSystemTestCase
  setup do
    @operator = users(:alice)
    @previous = ENV[OperatorCredential::OPERATOR_IDS_ENV]
    ENV[OperatorCredential::OPERATOR_IDS_ENV] = @operator.id
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
    ENV[OperatorCredential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator follows a failed incident to its workflow and sees what failed and why" do
    visit operator_incidents_path
    assert_text @incident.identifier
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-incidents.png"))

    find("a[href=\"#{operator_incident_path(@incident)}\"]").click
    assert_text "invite_responders"
    click_button "Show the error", match: :first
    assert_text "not_in_channel"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-incident.png"))

    visit operator_workflow_path(@workflow)
    assert_text(/selected step/i)
    assert_selector "button[aria-pressed=true]", text: "invite_responders"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-workflow.png"))
  end
end
