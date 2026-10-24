require_relative "test_helper"

class SolidWorkflow::WaitingTest < ActiveSupport::TestCase
  include DefinedWorkflowTestHelper

  setup { setup_defined_workflow }

  test "a delay parks the step and the run, and wakes once its time came" do
    definition = { "steps" => [ step("pause", "delay", { "minutes" => 30 }), step("after", "echo") ], "edges" => [ edge("pause", "after") ] }

    workflow = run_definition(definition)

    assert workflow.waiting?
    pause = workflow.steps.find_by!(name: "pause")
    assert pause.waiting?
    assert_in_delta 30.minutes.from_now, pause.run_at, 5

    perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(pause.id) }
    assert pause.reload.waiting?, "an early wake leaves it parked"

    travel 31.minutes do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(pause.id) }
    end

    assert workflow.reload.succeeded?
    assert_equal "succeeded", status_of(workflow, "after")
    assert workflow.events.exists?(event_type: SolidWorkflow::Events::Step::WOKEN)
  end

  test "a delay until a time of day waits for the next one in its zone" do
    travel_to Time.zone.parse("2026-10-13 10:00 UTC") do
      workflow = run_definition({ "steps" => [ step("morning", "delay", { "until" => "09:00", "time_zone" => "Europe/Belgrade" }) ], "edges" => [] })

      assert_equal Time.zone.parse("2026-10-14 07:00 UTC"), workflow.steps.first.run_at
    end
  end

  test "once at starts the run waiting and runs its first steps at that time" do
    at = 2.hours.from_now
    workflow = run_definition({ "steps" => [ step("first", "echo"), step("second", "echo") ], "edges" => [ edge("first", "second") ] }, not_before: at)

    assert workflow.waiting?
    assert_equal "waiting", status_of(workflow, "first")
    assert_equal "pending", status_of(workflow, "second")

    travel_to at + 1.second do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(workflow.steps.find_by!(name: "first").id) }
    end

    assert workflow.reload.succeeded?
  end

  test "a wait for event resumes on its signal with the payload, and takes the received route" do
    definition = {
      "steps" => [ step("deploy_done", "wait_for_event", { "event" => "deploy.finished", "key" => "{{inputs.service}}" }, timeout_seconds: 3600),
                   step("got_it", "echo", { "outcome" => "{{steps.deploy_done.event.outcome}}" }), step("gave_up", "echo") ],
      "edges" => [ edge("deploy_done", "got_it", "received"), edge("deploy_done", "gave_up", "timed_out") ]
    }
    workflow = run_definition(definition, context: { "inputs" => { "service" => "web" } })
    assert_equal "deploy.finished:web", workflow.steps.find_by!(name: "deploy_done").signal_key

    assert_equal 0, SolidWorkflow.signal!("deploy.finished:api", { "outcome" => "ok" })
    delivered = nil
    perform_enqueued_jobs { delivered = SolidWorkflow.signal!("deploy.finished:web", { "outcome" => "ok" }) }

    assert_equal 1, delivered
    assert workflow.reload.succeeded?
    assert_equal "ok", output_of(workflow, "got_it")["outcome"]
    assert_equal "bypassed", status_of(workflow, "gave_up")
    assert_equal "received", output_of(workflow, "deploy_done")["outcome"]
  end

  test "a wait for event that runs out of time takes its timed out route" do
    definition = {
      "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600), step("got_it", "echo"), step("gave_up", "echo") ],
      "edges" => [ edge("reply", "got_it", "received"), edge("reply", "gave_up", "timed_out") ]
    }
    workflow = run_definition(definition)
    reply = workflow.steps.find_by!(name: "reply")

    travel 11.minutes do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(reply.id) }
    end

    assert workflow.reload.succeeded?
    assert_equal "succeeded", status_of(workflow, "gave_up")
    assert_equal "bypassed", status_of(workflow, "got_it")
  end

  test "a wait for event that runs out of time with nothing on its timed out route fails the run saying why, without trying again" do
    definition = {
      "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600, retry: { "max_attempts" => 3 }), step("got_it", "echo") ],
      "edges" => [ edge("reply", "got_it", "received") ]
    }
    workflow = run_definition(definition)
    reply = workflow.steps.find_by!(name: "reply")

    travel 11.minutes do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(reply.id) }
    end

    assert workflow.reload.failed?
    reply.reload
    assert reply.failed?
    assert_equal 1, reply.attempts
    assert_match "reply timed out after 10 minutes.", reply.last_error
    assert_equal "timed_out", reply.route
    assert_equal "timed_out", reply.output["outcome"]
    assert_equal "cancelled", status_of(workflow, "got_it")
  end

  test "an attempt that no longer holds its step leaves the route the step took since alone" do
    workflow = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600) ], "edges" => [] })
    reply = workflow.steps.sole
    reply.update_columns(status: "running")
    moved_on = SolidWorkflow::Routed.new(output: { "outcome" => "timed_out" }, route: "timed_out", failure: "reply timed out.")
    TestDefinedWorkflow.any_instance.stubs(:run_step).with do |*|
      SolidWorkflow::Step.where(id: reply.id).update_all(route: "received", updated_at: 1.minute.from_now)
      true
    end.returns(moved_on)

    assert_raises(RuntimeError) { reply.reload.execute! }

    assert_equal "received", reply.reload.route
  end

  test "a wait for event alone that runs out of time fails the run, and its failure setting still decides whether the run carries on" do
    alone = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600) ], "edges" => [] })
    tolerated = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600, on_failure: "continue") ], "edges" => [] })

    travel 11.minutes do
      [ alone, tolerated ].each do |workflow|
        perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(workflow.steps.sole.id) }
      end
    end

    assert alone.reload.failed?
    assert tolerated.reload.succeeded?
    assert tolerated.steps.sole.failed?
  end

  test "a wait for event that hears its event with nothing on its received route succeeds as before" do
    definition = { "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600), step("gave_up", "echo") ],
                   "edges" => [ edge("reply", "gave_up", "timed_out") ] }
    workflow = run_definition(definition)

    perform_enqueued_jobs { SolidWorkflow.signal!("reply", { "said" => "yes" }) }

    assert workflow.reload.succeeded?
    assert_equal "bypassed", status_of(workflow, "gave_up")
  end

  test "a wake that lands while the step is still running is not lost" do
    workflow = run_definition({ "steps" => [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600) ], "edges" => [] })
    reply = workflow.steps.find_by!(name: "reply")
    reply.update_columns(status: "running")

    perform_enqueued_jobs do
      SolidWorkflow::Step.where(id: reply.id).update_all(signal_payload: { "said" => "yes" })
      reply.wake!(reason: "test")
      assert reply.reload.running?
      reply.park!(SolidWorkflow::Park.new(signal_key: "reply"), seen_wakes: 0)
    end

    assert workflow.reload.succeeded?
    assert_equal({ "said" => "yes" }, output_of(workflow, "reply")["event"])
  end

  test "a for each runs the steps inside once per item and hands back each in order" do
    definition = {
      "steps" => [
        step("services", "echo", { "names" => %w[web api worker] }),
        step("each", "for_each", { "items" => "{{steps.services.names}}", "concurrency" => 2,
                                   "steps" => [ step("look", "echo", { "service" => "{{item}}", "at" => "{{index}}", "from" => "{{steps.services.names}}" }) ],
                                   "edges" => [] }),
        step("after", "echo", { "count" => "{{steps.each.count}}" })
      ],
      "edges" => [ edge("services", "each"), edge("each", "after") ]
    }

    workflow = run_definition(definition)

    assert workflow.succeeded?, workflow.timeline.inspect
    results = output_of(workflow, "each")["results"]
    assert_equal %w[web api worker], results.map { |result| result["look"]["service"] }
    assert_equal [ 0, 1, 2 ], results.map { |result| result["look"]["at"] }
    assert_equal %w[web api worker], results.first["look"]["from"]
    assert_equal 3, output_of(workflow, "after")["count"]
    assert_equal [ [ 0 ], [ 1 ], [ 2 ] ], workflow.steps.find_by!(name: "each").children.map { |child| child.context["iteration"] }.sort
  end

  test "a for each starts at most its concurrency of items at once, and the next as one ends" do
    definition = {
      "steps" => [ step("each", "for_each", { "items" => %w[web api worker], "concurrency" => 2,
                                              "steps" => [ step("hold", "wait_for_event", { "event" => "go", "key" => "{{item}}" }, timeout_seconds: 600) ],
                                              "edges" => [] }) ],
      "edges" => []
    }

    workflow = run_definition(definition)
    each_step = workflow.steps.sole
    assert_equal [ 0, 1 ], each_step.children.map { |child| child.context["index"] }.sort

    perform_enqueued_jobs { SolidWorkflow.signal!("go:web", {}) }
    assert_equal [ 0, 1, 2 ], each_step.children.reload.map { |child| child.context["index"] }.sort
    assert workflow.reload.waiting?

    perform_enqueued_jobs do
      SolidWorkflow.signal!("go:api", {})
      SolidWorkflow.signal!("go:worker", {})
    end
    assert workflow.reload.succeeded?
    assert_equal 3, output_of(workflow, "each")["count"]
  end

  test "a for each over nothing finishes at once" do
    definition = { "steps" => [ step("each", "for_each", { "items" => [], "steps" => [ step("look", "echo") ], "edges" => [] }) ], "edges" => [] }

    assert_equal({ "count" => 0, "results" => [] }, output_of(run_definition(definition), "each"))
  end

  test "an item that fails ends the for each and cancels the rest" do
    definition = {
      "steps" => [ step("each", "for_each", { "items" => [ 1, 2, 3 ], "concurrency" => 3,
                                              "steps" => [ step("try", "fail", { "terminal" => true }) ], "edges" => [] }) ],
      "edges" => []
    }

    workflow = run_definition(definition)

    assert workflow.failed?
    assert_match "did not finish", workflow.steps.find_by!(name: "each").last_error
    assert workflow.steps.find_by!(name: "each").children.all?(&:completed?)
  end

  test "run workflow starts the sub workflow with its inputs and hands back its outputs" do
    TestDefinedWorkflow.sub_definition = { "steps" => [ step("double", "echo", { "n" => "{{inputs.n}}" }) ], "edges" => [], "outputs" => { "answer" => "{{steps.double.n}}" } }
    definition = { "steps" => [ step("call", "run_workflow", { "workflow" => "doubler", "inputs" => { "n" => 21 } }), step("after", "echo", { "got" => "{{steps.call.answer}}" }) ],
                   "edges" => [ edge("call", "after") ] }

    workflow = run_definition(definition)

    assert workflow.succeeded?
    assert_equal 21, output_of(workflow, "after")["got"]
    child = workflow.steps.find_by!(name: "call").children.sole
    assert_equal({ "answer" => 21 }, child.result)
  end

  test "a sub workflow that fails fails the step that ran it" do
    TestDefinedWorkflow.sub_definition = { "steps" => [ step("broken", "fail", { "terminal" => true }) ], "edges" => [] }
    workflow = run_definition({ "steps" => [ step("call", "run_workflow", { "workflow" => "broken" }) ], "edges" => [] })

    assert workflow.failed?
    assert_match "failed", workflow.steps.find_by!(name: "call").last_error
  end

  test "a step that waits past its time limit fails and cancels what it started" do
    TestDefinedWorkflow.sub_definition = { "steps" => [ step("hold", "wait_for_event", { "event" => "never" }, timeout_seconds: 86_400) ], "edges" => [] }
    workflow = run_definition({ "steps" => [ step("call", "run_workflow", { "workflow" => "slow" }, timeout_seconds: 60) ], "edges" => [] })
    call = workflow.steps.find_by!(name: "call")
    assert call.waiting?

    travel 2.minutes do
      perform_enqueued_jobs { SolidWorkflow::WakeJob.perform_now(call.id) }
    end

    assert workflow.reload.failed?
    assert_match "time limit", call.reload.last_error
    assert call.children.sole.cancelled?
  end

  test "an attempt past its step's time limit fails and retries, and the late attempt changes nothing" do
    definition = { "steps" => [ step("call", "slow", {}, timeout_seconds: 30, retry: { "max_attempts" => 2, "backoff" => "fixed", "backoff_seconds" => 1 }) ], "edges" => [] }
    TestDefinedWorkflow.held = true
    workflow = TestDefinedWorkflow.start!(@subject, definition: definition)
    TestDefinedWorkflow.held = false
    call = workflow.steps.sole
    call.update_columns(status: "running", attempts: 1, claimed_by: "first-job", timeout_at: 1.second.ago, updated_at: 1.minute.ago)

    SolidWorkflow::StepTimeoutJob.perform_now(call.id)

    call.reload
    assert call.pending?
    assert_match "time limit", call.last_error
    assert workflow.events.exists?(event_type: SolidWorkflow::Events::Step::TIMED_OUT)
    assert_not call.mark_failed!(RuntimeError.new("late"), claimed_by: "first-job")
    assert call.reload.pending?
  end

  test "cancelling a run cancels the runs its steps started" do
    TestDefinedWorkflow.sub_definition = { "steps" => [ step("hold", "wait_for_event", { "event" => "never" }, timeout_seconds: 600) ], "edges" => [] }
    workflow = run_definition({ "steps" => [ step("call", "run_workflow", { "workflow" => "slow" }) ], "edges" => [] })

    workflow.cancel!(reason: "test", by: "someone")

    assert workflow.reload.cancelled?
    assert workflow.steps.sole.cancelled?
    assert workflow.steps.sole.children.sole.cancelled?
  end

  test "a waiting run can be paused and resumed" do
    workflow = run_definition({ "steps" => [ step("pause", "delay", { "minutes" => 5 }) ], "edges" => [] })

    workflow.pause!(reason: "look", by: "operator")
    assert workflow.reload.paused?

    workflow.resume!(by: "operator")
    assert workflow.reload.waiting?
  end

  test "the sweeper wakes a parked step whose wake was lost" do
    workflow = run_definition({ "steps" => [ step("pause", "delay", { "minutes" => 5 }) ], "edges" => [] })

    travel 6.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end

    assert workflow.reload.succeeded?
  end
end
