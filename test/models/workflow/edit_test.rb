require "test_helper"

class Workflow::EditTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check")
  end

  def step(id, kind = "delay", config = { "seconds" => 1 }) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def edit(operation, payload, by: @alice, **options) = @workflow.edit!(operation: operation, payload: payload, by: by, **options)

  def draft = @workflow.reload.draft

  def publish_current!
    draft.publish!(by: @alice)
    @workflow.reload
  end

  test "each edit is one attributed operation that moves the draft's revision on" do
    added = edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") }, by: @bob)
    edit(Workflow::Edit::OPERATION_CONNECT, { "from" => "check", "to" => "tell" })
    edit(Workflow::Edit::OPERATION_MOVE_STEP, { "step_id" => "tell", "position" => { "x" => 120, "y" => 40 } })
    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "seconds" => 30 }, "timeout_seconds" => 90 } })
    edit(Workflow::Edit::OPERATION_CHANGE_TRIGGER, { "trigger" => { "kind" => "manual", "inputs" => [ { "key" => "region", "question" => "Which region?" } ] } })

    assert_equal Workflow::Edit::STATUS_APPLIED, added.status
    assert_equal [ "check" ], added.targets
    assert_equal 0, added.base_revision
    assert_equal 1, added.applied_revision
    assert_equal 6, draft.revision
    assert_equal [ { "from" => "check", "to" => "tell" } ], draft.edges
    assert_equal({ "x" => 120, "y" => 40 }, draft.steps.last["position"])
    assert_equal({ "seconds" => 30 }, draft.steps.first["config"])
    assert_equal 90, draft.steps.first["timeout_seconds"]
    assert_equal "region", draft.trigger["inputs"].first["key"]
    assert_equal [ @alice, @bob, @alice, @alice, @alice, @alice ], @workflow.edits.order(:applied_revision).map(&:author)

    edit(Workflow::Edit::OPERATION_DISCONNECT, { "from" => "check", "to" => "tell" })
    edit(Workflow::Edit::OPERATION_REMOVE_STEP, { "step_id" => "tell" })
    assert_equal [], draft.edges
    assert_equal [ "check" ], draft.steps.map { |each| each["id"] }
  end

  test "a new step gets an id that never changes, and steps go inside a for each when named" do
    added = edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => { "name" => "each", "kind" => "for_each", "config" => { "items" => [] } } })
    loop_id = added.payload.dig("step", "id")

    assert_match(/\Astep_[a-z0-9]{12}\z/, loop_id)
    assert_equal [ loop_id ], added.targets

    edit(Workflow::Edit::OPERATION_ADD_STEP, { "within" => loop_id, "step" => step("inside") })
    edit(Workflow::Edit::OPERATION_RENAME, { "step_id" => "inside", "name" => "look" })
    assert_equal [ "look" ], draft.steps.first.dig("config", "steps").map { |each| each["name"] }
  end

  test "renaming a step rewrites every reference to it" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell", "delay", { "seconds" => "{{steps.check.n}} and {{ steps.check }} not {{steps.checked.n}}" }) })

    edit(Workflow::Edit::OPERATION_RENAME, { "step_id" => "check", "name" => "look" })

    assert_equal "{{steps.look.n}} and {{ steps.look }} not {{steps.checked.n}}", draft.steps.last.dig("config", "seconds")
    assert_equal "check", draft.steps.first["id"]
  end

  test "renaming the workflow changes its name at once" do
    renamed = edit(Workflow::Edit::OPERATION_RENAME, { "name" => "Morning check" })

    assert_equal "Morning check", @workflow.reload.name
    assert_equal [ Workflow::Edit::TARGET_WORKFLOW ], renamed.targets
  end

  test "an edit made on an older revision lands on top when it touches something else" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") })
    seen = draft.revision

    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "seconds" => 5 } } }, by: @bob, base_revision: seen)
    late = edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "tell", "changes" => { "config" => { "seconds" => 7 } } }, base_revision: seen)

    assert_equal seen, late.base_revision
    assert_equal seen + 2, late.applied_revision
    assert_equal [ 5, 7 ], draft.steps.map { |each| each.dig("config", "seconds") }
  end

  test "an edit to a step someone changed since is refused, naming who" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    seen = draft.revision
    edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "seconds" => 5 } } }, by: @bob, base_revision: seen)

    error = assert_raises(Workflow::Edit::Refused) do
      edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "seconds" => 9 } } }, base_revision: seen)
    end

    assert_equal "#{@bob.actor_display_name} changed this since you looked, so look again before changing it.", error.message
    assert_equal 5, draft.steps.first.dig("config", "seconds")
  end

  test "an edit to a step someone removed is refused" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    edit(Workflow::Edit::OPERATION_REMOVE_STEP, { "step_id" => "check" })

    error = assert_raises(Workflow::Edit::Refused) { edit(Workflow::Edit::OPERATION_MOVE_STEP, { "step_id" => "check", "position" => { "x" => 1, "y" => 1 } }) }
    assert_equal "That step is no longer in the workflow.", error.message
  end

  test "a guarded save never overwrites an edit that landed first" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    current = draft
    stale = Workflow::Version.find(current.id)
    current.apply_edit!({ author_kind: Workflow::AUTHOR_PERSON, author: @bob, operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => step("tell") } })

    stale.apply_edit!({ author_kind: Workflow::AUTHOR_PERSON, author: @alice, operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => step("note") } },
                      base_revision: 1)

    assert_equal %w[check tell note], draft.steps.map { |each| each["id"] }
    assert_equal 3, draft.revision
  end

  test "Halon edits a workflow it is building alone directly" do
    built = edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") }, by: nil, halon: true, reason: "You asked for a check in 30 minutes.")

    assert_equal Workflow::Edit::STATUS_APPLIED, built.status
    assert draft.by_halon?
    assert_equal "You asked for a check in 30 minutes.", built.reason
  end

  test "Halon's edit to a live workflow is a proposal a person accepts or dismisses" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })
    publish_current!
    change_set = SecureRandom.uuid

    proposal = edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "check", "changes" => { "config" => { "seconds" => 60 } } },
                    by: nil, halon: true, reason: "The check timed out twice.", change_set_id: change_set)
    other = edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") }, by: nil, halon: true, reason: "Tell the team.", change_set_id: change_set)

    assert proposal.proposed?
    assert_nil draft, "nothing changes until a person accepts"
    assert_equal [ proposal, other ], @workflow.proposals.to_a
    assert_equal @workflow.live_version, proposal.version

    proposal.accept!(by: @bob)
    assert_equal Workflow::Edit::STATUS_ACCEPTED, proposal.status
    assert_equal @bob, proposal.decided_by
    assert_equal draft, proposal.version
    assert_equal 60, draft.steps.first.dig("config", "seconds")

    other.dismiss!(by: @bob)
    assert_equal Workflow::Edit::STATUS_DISMISSED, other.status
    assert_equal [ "check" ], draft.steps.map { |each| each["id"] }
    assert_raises(Workflow::Edit::Refused) { other.accept!(by: @alice) }
  end

  test "Halon proposes rather than writing into a draft a person touched" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") })

    proposal = edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("tell") }, by: nil, halon: true, reason: "Tell the team.")

    assert proposal.proposed?
    assert_equal draft, proposal.version
    assert_equal [ "check" ], draft.steps.map { |each| each["id"] }
  end

  test "a value that looks like a credential is never kept in a step" do
    edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("call") })

    error = assert_raises(Workflow::Edit::Refused) do
      edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "call", "changes" => { "config" => { "header" => "Bearer ghp_#{'a' * 36}" } } })
    end

    assert_match "looks like it holds a secret", error.message
    assert_not draft.steps.first["config"].key?("header")
    assert_not draft.update(steps: [ step("call", "delay", { "token" => "ghp_#{'a' * 36}" }) ])

    publish_current!
    assert_raises(Workflow::Edit::Refused) do
      edit(Workflow::Edit::OPERATION_CHANGE_CONFIG, { "step_id" => "call", "changes" => { "config" => { "token" => "ghp_#{'a' * 36}" } } },
           by: nil, halon: true, reason: "It needs the token.")
    end
    assert_empty @workflow.proposals
  end

  test "Halon's edits need a reason" do
    assert_raises(ActiveRecord::RecordInvalid) do
      edit(Workflow::Edit::OPERATION_ADD_STEP, { "step" => step("check") }, by: nil, halon: true)
    end
  end
end
