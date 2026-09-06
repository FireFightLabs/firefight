require "test_helper"

class Slack::Modals::IncidentCreationTest < ActiveSupport::TestCase
  test "a test declare carries its state and says what a test incident is" do
    view = Slack::Modals::IncidentCreation.build(workspace: workspaces(:slack_workspace_one), private_metadata: ModalState.encode(test: true), test: true)

    assert_equal ModalState.encode(test: true), view[:private_metadata]
    assert_equal Slack::Modals::IncidentCreation::TEST_NOTE, view[:blocks].first[:elements].first[:text]
  end

  test "a plain declare carries no state and no note" do
    view = Slack::Modals::IncidentCreation.build(workspace: workspaces(:slack_workspace_one))

    assert_not view.key?(:private_metadata)
    assert_not_equal "context", view[:blocks].first[:type]
  end
end
