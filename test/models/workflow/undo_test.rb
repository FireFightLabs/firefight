require "test_helper"

# Undo Halon's change takes Halon's edits back out as a person's edits, keeping what people did around them.
class Workflow::UndoTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check")
  end

  def step(id, kind = DefinedWorkflow::KIND_DELAY, config = { "minutes" => 1 }) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def edit(operation, payload, halon: false) = @workflow.reload.edit!(operation: operation, payload: payload, by: halon ? nil : @alice, halon: halon,
                                                                       reason: halon ? "Halon thought so." : nil)

  def draft = @workflow.reload.draft

  test "a version made again from where it started and its edits is the version" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("first") })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("loop", DefinedWorkflow::KIND_FOR_EACH, { "items" => [ 1 ] }) })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "within" => "loop", "step" => step("inner") })
    edit(Workflow::Edit::OPERATION_CONNECT, { "from" => "first", "to" => "loop" })
    edit(Workflow::Edit::OPERATION_RENAME, { "step_id" => "first", "name" => "wait" })

    assert_equal draft.snapshot, draft.content_without([])
  end

  test "Halon's step and the connections to it go, and a person's change on top of it goes with it" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    @workflow.draft.publish!(by: @alice)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") }, halon: true)
    edit(Workflow::Edit::OPERATION_CONNECT, { "from" => "check", "to" => "tell" }, halon: true)
    @workflow.proposals.each { |proposal| proposal.accept!(by: @alice) }
    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "tell", "changes" => { "config" => { "minutes" => 7 } } })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("other") })
    halon = @workflow.edits.landed.where(author_kind: Workflow::AUTHOR_HALON).to_a

    made = @workflow.undo_halon!(halon, by: @alice)

    assert_equal %w[check other], draft.steps.map { |each| each["id"] }
    assert_equal [], draft.edges
    assert_equal [ Workflow::Editing::UNDO_REASON ], made.map(&:reason).uniq
    assert_equal 1, made.map(&:change_set_id).uniq.size
  end

  test "Halon's change to a live version is undone into a new draft" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") }, halon: true)
    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "minutes" => 3 }, "timeout_seconds" => 60 } }, halon: true)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") })
    @workflow.draft.publish!(by: @alice)
    change = @workflow.edits.landed.where(author_kind: Workflow::AUTHOR_HALON, operation: Workflow::Edit::OPERATION_CHANGE_CONFIG).to_a

    @workflow.undo_halon!(change, by: @alice)

    check = draft.steps.find { |each| each["id"] == "check" }
    assert_equal({ "minutes" => 1 }, check["config"])
    assert_nil check["timeout_seconds"]
    assert_equal 3, @workflow.live_version.steps.find { |each| each["id"] == "check" }.dig("config", "minutes")
  end

  test "Halon's change to the live version under an open draft is undone in the draft, keeping what the draft changed" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") }, halon: true)
    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "minutes" => 3 } } }, halon: true)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") })
    @workflow.draft.publish!(by: @alice)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("later") })
    edit(Workflow::Edit::OPERATION_RENAME, { "step_id" => "check", "name" => "first_check" })
    change = @workflow.edits.landed.where(author_kind: Workflow::AUTHOR_HALON, operation: Workflow::Edit::OPERATION_CHANGE_CONFIG).to_a

    @workflow.undo_halon!(change, by: @alice)

    check = draft.steps.find { |each| each["id"] == "check" }
    assert_equal({ "minutes" => 1 }, check["config"])
    assert_equal "first_check", check["name"]
    assert_equal %w[check tell later], draft.steps.map { |each| each["id"] }
  end

  test "every change of Halon's the canvas lists, in the draft and the live version under it, is undone together" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    @workflow.draft.publish!(by: @alice)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") }, halon: true)
    @workflow.proposals.each { |proposal| proposal.accept!(by: @alice) }
    @workflow.draft.publish!(by: @alice)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("page") }, halon: true)
    @workflow.proposals.each { |proposal| proposal.accept!(by: @alice) }
    halon = @workflow.reload.edits.landed.where(author_kind: Workflow::AUTHOR_HALON, version_id: @workflow.undoable_version_ids).to_a

    assert_equal 2, halon.size
    @workflow.undo_halon!(halon, by: @alice)

    assert_equal %w[check], draft.steps.map { |each| each["id"] }
  end

  test "a person's change cannot be undone as Halon's, nor a change on a retired version" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })

    assert_equal "Only a change Halon made can be undone here.", @workflow.undo_blocked_reason(@workflow.edits.to_a)
    assert_raises(Workflow::Edit::Refused) { @workflow.undo_halon!(@workflow.edits.to_a, by: @alice) }
  end

  test "undoing twice says it is already undone" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") }, halon: true)
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") })
    halon = @workflow.edits.where(author_kind: Workflow::AUTHOR_HALON).to_a
    @workflow.undo_halon!(halon, by: @alice)

    error = assert_raises(Workflow::Edit::Refused) { @workflow.undo_halon!(halon, by: @alice) }
    assert_equal "Halon's change is already undone.", error.message
  end
end
