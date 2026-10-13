require "test_helper"

class Workflow::Edit::WordingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check")
  end

  def step(id) = { "id" => id, "name" => id, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 1 } }

  def edit(operation, payload, **options) = @workflow.reload.edit!(operation: operation, payload: payload, by: @alice, **options)

  test "each change says what happened and who did it, naming steps by their title even once they are gone" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check_logs") })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") })
    connect = edit(Workflow::Edit::OPERATION_CONNECT, { "from" => "check_logs", "to" => "tell", "route" => "timed_out" })
    rename = edit(Workflow::Edit::OPERATION_RENAME, { "step_id" => "tell", "name" => "tell_ops" })
    remove = edit(Workflow::Edit::OPERATION_REMOVE_STEP, { "step_id" => "check_logs" })

    assert_equal "Check logs now leads to Tell on timed out.", connect.notice
    assert_equal "Alice Smith connected Check logs to Tell on timed out.", connect.sentence
    assert_equal "Tell was renamed to Tell ops.", rename.notice
    assert_equal "Check logs was removed.", remove.reload.notice
    assert_equal "Alice Smith removed Check logs.", remove.sentence
  end

  test "Halon's suggestion reads as what it would do" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    @workflow.draft.publish!(by: @alice)
    suggestion = @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_REMOVE_STEP, payload: { "step_id" => "check" }, by: nil, halon: true,
                                        reason: "It never finds anything.")

    assert_equal "Remove Check", suggestion.suggestion_words
    assert_equal "Halon removed Check.", suggestion.sentence
  end
end
