require "test_helper"

class Slack::Modals::IncidentCreationTest < ActiveSupport::TestCase
  test "a test declare carries its state and says what a test incident is" do
    view = Slack::Modals::IncidentCreation.build(workspace: workspaces(:slack_workspace_one), private_metadata: ModalState.encode(test: true), test: true)

    assert_equal ModalState.encode(test: true), view[:private_metadata]
    assert_equal Slack::Modals::IncidentCreation::TEST_NOTE, view[:blocks].first[:elements].first[:text]
  end

  test "a declare opened from an investigation starts with its question as the name, and keeps it when the form changes" do
    workspace = workspaces(:slack_workspace_one)
    run = workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )

    view = Slack::Modals::IncidentCreation.build(workspace: workspace, private_metadata: ModalState.encode(investigation_id: run.id))

    name = view[:blocks].find { |block| block[:block_id] == Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_NAME) }
    assert_equal "checkout is slow", name.dig(:element, :initial_value)
  end

  test "a declare opened from a run asked for in Slack is named by its question as Slack shows it" do
    workspace = workspaces(:slack_workspace_one)
    bob = workspace_memberships(:bob_workspace_one)
    run = workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => "<@#{bob.platform_user_id}> says *checkout* is slow &amp; :fire:" },
                                       source: Investigation::Brief::SOURCE_COMMAND)
    )

    view = Slack::Modals::IncidentCreation.build(workspace: workspace, private_metadata: ModalState.encode(investigation_id: run.id))

    name = view[:blocks].find { |block| block[:block_id] == Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_NAME) }
    assert_equal "@#{bob.display_name} says checkout is slow & 🔥", name.dig(:element, :initial_value)
  end

  test "a plain declare carries no state and no note" do
    view = Slack::Modals::IncidentCreation.build(workspace: workspaces(:slack_workspace_one))

    assert_not view.key?(:private_metadata)
    assert_not_equal "context", view[:blocks].first[:type]
  end
end
