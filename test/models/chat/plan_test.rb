require "test_helper"

# A plan Halon keeps for a request of more than one step. Each change carries its undo before it runs, a plan that
# changed something ends with a check that read it worked, and a failed change stops it with done, failed and not started.
class Chat::PlanTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @chat = @conversation.chat_record
  end

  RELEASE = [
    { "kind" => "read", "description" => "Read the latest commit on main", "place" => "GitHub" },
    { "kind" => "change", "description" => "Start the release workflow", "place" => "GitHub", "tool" => "github_run_workflow",
      "undo" => "Roll checkout back to the deploy before" },
    { "kind" => "check", "description" => "Check checkout's error rate and latency against normal", "place" => "checkout" }
  ].freeze

  def make(steps = RELEASE, **options)
    Chat::Plan.make!(chat: @chat, made_by: @alice, goal: "Release main to production", steps: steps.map(&:dup), **options)
  end

  def refused(&)
    error = assert_raises(Chat::Plan::Refused, &)
    error.message
  end

  test "a plan holds its goal and its steps in order, going from the start" do
    plan = make

    assert_equal [ Chat::Plan::STATUS_ACTIVE, "Release main to production" ], [ plan.status, plan.goal ]
    assert_equal [ [ 1, "read" ], [ 2, "change" ], [ 3, "check" ] ], plan.steps.map { |step| [ step.position, step.kind ] }
    assert plan.steps.all?(&:not_started?)
  end

  test "a change without its undo, a change with no check after it and a one step plan are refused with why" do
    assert_match "Step 2 changes something and has no undo", refused { make([ RELEASE[0], RELEASE[1].except("undo"), RELEASE[2] ]) }
    assert_match "ends with a check step after its last change", refused { make(RELEASE.first(2)) }
    assert_match "more than one step", refused { make([ RELEASE[0] ]) }
    assert_match "at most #{Chat::Plan::MAX_STEPS} steps", refused { make([ RELEASE[0] ] * 13) }
    assert_match "is a \"deploy\"", refused { make([ RELEASE[0], RELEASE[1].merge("kind" => "deploy") ]) }
    assert_match "goal", refused { Chat::Plan.make!(chat: @chat, made_by: @alice, goal: " ", steps: RELEASE) }
  end

  test "a plan never keeps a credential" do
    leaky = RELEASE[1].merge("undo" => "Set the key back to ghp_#{'a' * 36}")

    assert_match "looks like a secret", refused { make([ RELEASE[0], leaky, RELEASE[2] ]) }
  end

  test "a scheduled plan waits for approval, names the tool of each change, and is never set in the past or in a freeze" do
    saturday = 1.day.from_now.change(hour: 6)
    plan = make(run_at: saturday, time_zone: "Europe/Berlin")

    assert_equal [ Chat::Plan::STATUS_PROPOSED, nil ], [ plan.status, plan.started_at ]
    assert_match "names no tool", refused { make([ RELEASE[0], RELEASE[1].except("tool"), RELEASE[2] ], run_at: saturday) }
    assert_match "That time has passed", refused { make(run_at: 1.hour.ago) }

    freeze = Workspace::FreezeWindows::Window.new(name: "the launch", starts_at: saturday - 1.day, ends_at: saturday + 1.day)
    Workspace::FreezeWindows.stubs(:all).returns([ freeze ])
    assert_match "Changes are frozen for the launch until", refused { make(run_at: saturday, time_zone: "Europe/Berlin") }
  end

  test "a step moves from running to done, and a change takes an exact undo from what it returned" do
    plan = make
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_RUNNING)
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE, note: "main is at abc123", links: [ "https://github.com/acme/shop/commit/abc123", "not a link" ])
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE, undo: "Roll checkout back to deploy d-41")

    first, second = plan.steps.reload.first(2)
    assert_equal [ "done", "main is at abc123", [ "https://github.com/acme/shop/commit/abc123" ] ], [ first.status, first.note, first.links ]
    assert_equal "Roll checkout back to deploy d-41", second.undo
    assert first.started_at && first.finished_at
  end

  test "a failed change stops the plan, and says what is done, what failed and why, and what has not started" do
    plan = make([ RELEASE[0], RELEASE[1], RELEASE[1].merge("description" => "Deploy region 2"), RELEASE[1].merge("description" => "Deploy region 3"), RELEASE[2] ])
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(3, status: Chat::Plan::Step::STATUS_FAILED, note: "The provider said quota exceeded")

    assert plan.reload.stopped?
    assert_equal "Step 3 failed. The provider said quota exceeded.", plan.stop_reason
    assert_equal "Done: steps 1 and 2. Failed: step 3. The provider said quota exceeded. Not started: steps 4 and 5.", plan.standing
  end

  test "a failed read does not stop the plan, and starting a step again after a stop takes it up again" do
    plan = make
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_FAILED, note: "Timed out")
    assert plan.reload.active?

    plan.move_step!(2, status: Chat::Plan::Step::STATUS_FAILED, note: "Rejected")
    assert plan.reload.stopped?
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_RUNNING)

    assert_equal [ Chat::Plan::STATUS_ACTIVE, nil ], [ plan.reload.status, plan.stop_reason ]
  end

  test "a check after a change needs a reading since it ended and a verdict, and one that did not hold stops the plan" do
    plan = make
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)

    assert_match "Read how it stands since the last change ended",
                 refused { plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE, verdict: "held", read_since: ->(_time) { false }) }
    assert_match "verdict", refused { plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE) }

    plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE, verdict: Chat::Plan::Step::VERDICT_NOT_HELD, note: "Errors are at 4%, normal is 0.2%")
    assert_equal "The check found the changes did not work. Errors are at 4%, normal is 0.2%.", plan.reload.stop_reason
  end

  test "a check that says nothing connected could tell needs no reading, and lets the plan finish" do
    plan = make
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE, verdict: Chat::Plan::Step::VERDICT_UNKNOWN,
                       note: "No connection reads checkout's metrics.", read_since: ->(_time) { false })

    assert plan.finish!(outcome: "Released, unchecked.", next_step: "Shall I show you how to connect metrics?").completed?
  end

  test "a plan finishes only once every step ended, a change was checked, and a next step is given" do
    plan = make
    assert_match "Steps 1, 2, and 3 have not ended", refused { plan.finish!(outcome: "Done", next_step: "Watch it") }

    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(3, status: Chat::Plan::Step::STATUS_SKIPPED)
    assert_match "Step 2 changed something, so check it worked", refused { plan.finish!(outcome: "Done", next_step: "Watch it") }

    plan.revise!([ { "kind" => "check", "description" => "Check checkout against normal" } ])
    plan.move_step!(4, status: Chat::Plan::Step::STATUS_DONE, verdict: Chat::Plan::Step::VERDICT_HELD, note: "Error rate 0.1%, normal 0.2%")
    assert_match "next_step", refused { plan.finish!(outcome: "Done", next_step: "") }

    plan.finish!(outcome: "Release 1.4 is live and healthy.", next_step: "Shall I watch it for an hour?", links: [ "https://github.com/acme/shop/actions/runs/46" ])
    assert_equal [ Chat::Plan::STATUS_COMPLETED, "Shall I watch it for an hour?", [ "https://github.com/acme/shop/actions/runs/46" ] ],
                 [ plan.status, plan.next_step, plan.links ]
  end

  test "revising keeps the steps that started, in their order, and replaces the rest" do
    plan = make
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_RUNNING)
    plan.revise!([ { "kind" => "check", "description" => "Read checkout's health" }, { "kind" => "read", "description" => "Read the release notes" } ])

    assert_equal [ [ 1, "Start the release workflow", "running" ], [ 2, "Read checkout's health", "not_started" ], [ 3, "Read the release notes", "not_started" ] ],
                 plan.steps.reload.map { |step| [ step.position, step.description, step.status ] }
  end

  test "nothing in a plan waiting for its time starts, and an approved one is not revised" do
    plan = make(run_at: 1.day.from_now, time_zone: "UTC")

    assert_match "nothing in it starts before then", refused { plan.move_step!(1, status: Chat::Plan::Step::STATUS_RUNNING) }
    plan.approve!(by: @alice)
    assert_match "Cancel it with cancel_plan", refused { plan.revise!(RELEASE) }
  end

  test "approving, claiming the run and undoing are each won once" do
    plan = make(run_at: 1.day.from_now, time_zone: "UTC")

    assert plan.approve!(by: @alice)
    assert_not Chat::Plan.find(plan.id).approve!(by: @bob)
    assert_equal [ Chat::Plan::STATUS_SCHEDULED, @alice ], [ plan.status, plan.approved_by ]
    assert_not plan.claim_run!
    assert plan.claim_run!(2.days.from_now)
    assert_not Chat::Plan.find(plan.id).claim_run!(2.days.from_now)
    assert plan.claim_undo!
    assert_not Chat::Plan.find(plan.id).claim_undo!
  end

  test "a scheduled run skips asking only for the tools its approved changes named" do
    plan = make(run_at: 1.day.from_now, time_zone: "UTC")
    assert_empty plan.approved_tools

    plan.approve!(by: @alice)
    assert_equal [ "github_run_workflow" ], plan.approved_tools
  end

  test "the undo puts back each change that went through, newest first, then checks it is back" do
    plan = make([ RELEASE[0], RELEASE[1], RELEASE[1].merge("description" => "Turn the flag on", "undo" => "Turn the flag off", "place" => "Flags"), RELEASE[2] ])
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE)

    steps = plan.undo_steps
    assert_equal [ "Put back step 3: Turn the flag off", "Put back step 2: Roll checkout back to the deploy before" ], steps.first(2).pluck("description")
    assert_equal [ "change", "change", "check" ], steps.pluck("kind")
    assert_equal "Flags and GitHub", steps.last["place"]
  end

  test "who may press something on a plan: its owner in a dashboard chat, anyone in the channel for a chat in one" do
    plan = make

    assert plan.may_act?(@alice)
    assert_not plan.may_act?(@bob)
    assert_equal "Only Alice Smith can do that.", plan.only_who_may

    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "1.1")
    assert plan.reload.may_act?(@bob)
    assert_not plan.may_act?(workspace_memberships(:alice_workspace_two))
  end

  test "undo is offered once a plan that changed something stopped or finished, and never for an undo" do
    plan = make
    assert_equal "Undo is offered once the plan has stopped or finished.", plan.undo_blocked_reason(@alice)

    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_FAILED, note: "Rejected")
    assert_equal "Nothing in this plan changed anything, so there is nothing to undo.", plan.reload.undo_blocked_reason(@alice)
    assert_equal "Only a plan that stopped can be tried again.", make.retry_blocked_reason(@alice)
    assert_nil plan.retry_blocked_reason(@alice)
  end
end
