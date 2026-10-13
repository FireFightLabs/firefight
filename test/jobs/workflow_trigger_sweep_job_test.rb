require "test_helper"

class WorkflowTriggerSweepJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
  end

  def scheduled(name, trigger)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    workflow.open_draft!(by: @alice).update!(trigger: trigger, steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "minutes" => 5 } } ])
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    workflow.reload
  end

  test "starts a workflow once its time comes, once, and moves its next time on" do
    travel_to Time.zone.parse("2026-10-13 06:58 UTC") do
      workflow = scheduled("Morning", { "kind" => "schedule", "repeat" => "days", "days" => [ 1, 2, 3, 4, 5 ], "at" => "09:00", "time_zone" => "Europe/Belgrade", "inputs" => [] })
      assert_equal Time.zone.parse("2026-10-13 07:00 UTC"), workflow.next_run_at

      travel 3.minutes
      WorkflowTriggerSweepJob.perform_now
      WorkflowTriggerSweepJob.perform_now

      run = workflow.runs.sole
      assert_equal Workflow::Trigger::KIND_SCHEDULE, run.trigger_kind
      assert_equal Workflow::Run::STARTED_BY_TRIGGER, run.started_by_kind
      assert_equal Time.zone.parse("2026-10-14 07:00 UTC"), workflow.reload.next_run_at
    end
  end

  test "a start that breaks is kept on that workflow with why and tried again next sweep, and the sweep starts the next" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      broken = scheduled("Broken", { "kind" => "once_at", "at" => "2026-10-13T12:10", "time_zone" => "UTC", "inputs" => [] })
      fine = scheduled("Fine", { "kind" => "once_at", "at" => "2026-10-13T12:10", "time_zone" => "UTC", "inputs" => [] })
      breaking = WorkflowRunService.new(broken)
      breaking.stubs(:start!).raises(ActiveRecord::StatementInvalid, "PG::QueryCanceled")
      starting = WorkflowRunService.new(fine)
      WorkflowRunService.stubs(:new).with { |workflow| workflow.id == broken.id }.returns(breaking)
      WorkflowRunService.stubs(:new).with { |workflow| workflow.id == fine.id }.returns(starting)

      travel 11.minutes
      WorkflowTriggerSweepJob.perform_now

      assert_equal "It could not start because of an error in Firefight.", broken.reload.trigger_refusal
      assert_equal Time.zone.parse("2026-10-13 12:10 UTC"), broken.next_run_at
      assert_empty broken.runs
      assert_nil fine.reload.trigger_refusal
      assert_equal 1, fine.runs.count

      WorkflowRunService.unstub(:new)
      WorkflowTriggerSweepJob.perform_now

      assert_equal "trigger:2026-10-13T12:10:00Z", broken.runs.sole.start_key
      assert_nil broken.reload.trigger_refusal
      assert_nil broken.next_run_at
    end
  end

  test "a one off that was only tested and then turned off is not done" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow = scheduled("Later", { "kind" => "once_at", "at" => "2026-10-13T14:30", "time_zone" => "UTC", "inputs" => [] })
      WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true)
      WorkflowPublishService.new(workflow).switch!(on: false)

      assert_not workflow.reload.done?
      assert_not Workflow.with_run_counts.find(workflow.id).done?
    end
  end

  test "a one off runs once and then has no next time" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow = scheduled("Later", { "kind" => "once_at", "at" => "2026-10-13T14:30", "time_zone" => "Europe/Belgrade", "inputs" => [] })

      travel 31.minutes
      WorkflowTriggerSweepJob.perform_now

      assert_equal 1, workflow.runs.count
      assert_nil workflow.reload.next_run_at
      assert workflow.done?
    end
  end

  test "a start the workflow's limits refuse is kept on it with why, and a later start clears it" do
    travel_to Time.zone.parse("2026-10-13 06:58 UTC") do
      workflow = scheduled("Busy", { "kind" => "schedule", "repeat" => "minutes", "every" => 5, "time_zone" => "UTC", "inputs" => [] })
      workflow.update!(runs_per_hour: 1)
      workflow.runs.create!(workspace: @workspace, version: workflow.live_version, trigger_kind: "manual", started_by_kind: "person", start_key: "earlier")

      travel 3.minutes
      WorkflowTriggerSweepJob.perform_now

      assert_match "already started 1 run in the last hour", workflow.reload.trigger_refusal
      assert_equal 1, workflow.runs.count
    end
  end

  test "nothing starts for a workspace without the workflows flag, and a switched off workflow has no next time" do
    travel_to Time.zone.parse("2026-10-13 06:58 UTC") do
      workflow = scheduled("Quiet", { "kind" => "schedule", "repeat" => "minutes", "every" => 5, "time_zone" => "UTC", "inputs" => [] })
      FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
      travel 3.minutes
      WorkflowTriggerSweepJob.perform_now
      assert_empty workflow.runs

      WorkflowPublishService.new(workflow).switch!(on: false)
      assert_nil workflow.reload.next_run_at
    end
  end
end
