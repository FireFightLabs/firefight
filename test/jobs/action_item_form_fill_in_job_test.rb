require "test_helper"

class ActionItemFormFillInJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @bob = workspace_memberships(:bob_workspace_one)
    @state = ModalState.encode(incident_id: @incident.id, channel_id: "C123", source_message_id: "1700000000.000100")
  end

  test "reads the message and fills the open form with it as readable text, up to the form's own limit" do
    Slack::Client.expects(:get_message).with { |arguments| arguments[:channel] == "C123" && arguments[:ts] == "1700000000.000100" }
                 .returns({ "ts" => "1700000000.000100", "user" => @bob.platform_user_id, "text" => "<@#{@bob.platform_user_id}> #{'slow ' * 1000}" })
    Slack::Client.expects(:update_modal).with do |args|
      initial = args[:view][:blocks].first.dig(:element, :initial_value)
      args[:view_id] == "V12345678" && args[:view][:callback_id] == Identifiers::CREATE_FOLLOWUP_MODAL &&
        initial.start_with?("@#{@bob.display_name} slow slow") && initial.length == Slack::Modals::ActionItemsForm::DESCRIPTION_LIMIT
    end.returns({ ok: true })

    ActionItemFormFillInJob.perform_now(@workspace.id, @incident.id, "followup", "V12345678", @state)
  end

  test "a message that can no longer be read leaves the form empty and says so in the log" do
    Slack::WorkspaceAdapter.any_instance.stubs(:fetch_message).raises(AdapterError::NotFound.new("message_not_found"))
    Slack::Client.expects(:update_modal).never
    Rails.logger.expects(:info).with { |line| line.include?("action_item_form.fill_in_failed") }

    ActionItemFormFillInJob.perform_now(@workspace.id, @incident.id, "action", "V12345678", @state)
  end

  test "an older message read back in place of a deleted one leaves the form empty" do
    Slack::Client.stubs(:get_message).returns({ "ts" => "1699999999.000900", "text" => "Something said earlier" })
    Slack::Client.expects(:update_modal).never

    ActionItemFormFillInJob.perform_now(@workspace.id, @incident.id, "action", "V12345678", @state)
  end

  test "a form closed before it is filled in is left alone and the job ends quietly" do
    Slack::Client.stubs(:get_message).returns({ "ts" => "1700000000.000100", "text" => "The database is slow" })
    Slack::WorkspaceAdapter.any_instance.stubs(:update_modal).raises(AdapterError::NotFound.new("not_found"))
    Rails.logger.expects(:info).with { |line| line.include?("action_item_form.fill_in_failed") }

    assert_nothing_raised { ActionItemFormFillInJob.perform_now(@workspace.id, @incident.id, "action", "V12345678", @state) }
  end

  test "an incident that is gone leaves nothing to fill in" do
    Slack::Client.expects(:get_message).never

    ActionItemFormFillInJob.perform_now(@workspace.id, SecureRandom.uuid, "action", "V12345678", @state)
  end
end
