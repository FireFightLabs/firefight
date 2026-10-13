require "test_helper"

class WorkflowRunEndServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @adapter = WorkspaceAdapter.for(@workspace).class
    Investigation.stubs(:unavailable_reason).returns(nil)
  end

  def published(name, steps:, edges: [])
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    workflow.open_draft!(by: @alice).update!(steps: steps, edges: edges)
    assert WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice).ok
    workflow.reload
  end

  def failing = published("Probe", steps: [ { "id" => "scan", "name" => "scan", "kind" => "run_skill", "config" => { "skill" => "probing_scan" } } ])

  def run!(workflow, **options)
    Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "error" => "The logs could not be read." })
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: "schedule", **options) }
    run.reload
  end

  test "a failed run is said to whoever published it when the workflow has no team, with Halon's suggested fix as a proposal" do
    workflow = failing
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).returns(
      FirefightAi::WorkflowRepair::Suggestion.new(reason: "The skill needs a focus on the shop service.", config: { "focus" => "shop" })
    )
    @adapter.any_instance.expects(:post_workflow_failure).with(has_entries(channel_id: @alice.platform_user_id, suggestion: true)).returns({})

    run = run!(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    proposal = workflow.proposals.sole
    assert proposal.by_halon?
    assert_equal run, proposal.source_run
    assert_equal "The skill needs a focus on the shop service.", proposal.reason
    assert run.told_at
  end

  test "Halon suggests a fix once per problem: on the first failure, and again only when a run fails at another step or in another way" do
    workflow = failing
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).twice.returns(nil)
    failing_with = lambda do |words|
      Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "error" => words })
      perform_enqueued_jobs { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: "schedule") }
    end

    failing_with.call("The logs could not be read after 3 tries at 09:00.")
    failing_with.call("The logs could not be read after 5 tries at 10:00.")
    failing_with.call("The skill probing_scan is not offered any more.")

    assert_equal 3, workflow.runs.where(status: Workflow::Run::STATUS_FAILED).count
  end

  test "Halon looks at each kind of failure once per published version, even when they take turns, and again after a new version is published" do
    workflow = failing
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    looked_at = []
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).with { |**given| looked_at << given[:error] }.returns(nil)
    failing_with = lambda do |words|
      Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "error" => words })
      perform_enqueued_jobs { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: "schedule") }
    end
    unreadable = "The logs could not be read."
    gone = "The skill probing_scan is not offered any more."

    [ unreadable, gone, unreadable, gone ].each { |words| failing_with.call(words) }
    assert_equal [ unreadable, gone ], looked_at

    workflow.open_draft!(by: @alice).update!(steps: [ { "id" => "scan", "name" => "scan", "kind" => "run_skill", "config" => { "skill" => "probing_scan", "focus" => "shop" } } ])
    assert WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice).ok
    failing_with.call(unreadable)
    assert_equal [ unreadable, gone, unreadable ], looked_at
  end

  test "a failure Halon could not look at, since the model call broke, is looked at again when a run fails the same way" do
    workflow = failing
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).twice.raises(FirefightAi::TransientError, "timed out").then.returns(nil)

    run!(workflow)
    assert_empty workflow.live_version.reload.repair_problem_keys
    run!(workflow)
    assert_equal 1, workflow.live_version.reload.repair_problem_keys.size
    run!(workflow)

    assert_equal 3, workflow.runs.where(status: Workflow::Run::STATUS_FAILED).count
  end

  test "a look at a failure that was stopped while the model answered is still told, and the failure is looked at again" do
    workflow = failing
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).twice.raises(FirefightAi::Canceled, "stopped").then.returns(nil)

    first = run!(workflow)
    assert first.told_at, "the failure is told without a suggestion"
    assert_empty workflow.live_version.reload.repair_problem_keys
    run!(workflow)
    assert_equal 1, workflow.live_version.reload.repair_problem_keys.size
  end

  test "a failed run is said in the channel of the team that owns the workflow" do
    workflow = failing
    workflow.update!(owner_team: catalog_entries(:platform_team))
    CatalogEntry.any_instance.stubs(:role_value).with(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL).returns("C0PLATFORM")
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter.any_instance.expects(:post_workflow_failure).with(has_entries(channel_id: "C0PLATFORM", suggestion: false)).returns({})

    run!(workflow)
  end

  test "a failure notice that could not be sent is not counted as told, and is sent again later with the fix Halon already suggested" do
    workflow = failing
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).once.returns(
      FirefightAi::WorkflowRepair::Suggestion.new(reason: "The skill needs a focus on the shop service.", config: { "focus" => "shop" })
    )
    @adapter.any_instance.expects(:post_workflow_failure).with(has_entries(channel_id: @alice.platform_user_id, suggestion: true))
            .twice.raises(AdapterError::ServerError, "internal_error").then.returns({})

    run = run!(workflow)

    assert run.told_at, "the job tried again and the notice landed"
    assert_equal 1, workflow.proposals.count
  end

  test "a failure notice waits for the next try while the platform is down, and the job is enqueued again" do
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    run = run!(failing)
    run.update_columns(told_at: nil)
    @adapter.any_instance.stubs(:post_workflow_failure).raises(AdapterError::Unavailable, "service_unavailable")

    assert_enqueued_with(job: WorkflowRunEndedJob, args: [ run.id ]) { WorkflowRunEndedJob.perform_now(run.id) }
    assert_nil run.reload.told_at
  end

  test "a run whose telling broke is left to be told again, and a job a stopped worker left is run again and takes back its own claim" do
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    run = run!(failing)
    run.update_columns(told_at: nil)

    @adapter.any_instance.stubs(:post_workflow_failure).raises(RuntimeError, "something else broke")
    assert_raises(RuntimeError) { WorkflowRunEndService.new(run, job_id: "job-1").ended! }
    assert_nil run.reload.telling_job_id, "a claim is given back whatever broke"

    run.update_columns(telling_job_id: "job-1")
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    WorkflowRunEndService.new(run, job_id: "job-2").ended!
    assert_nil run.reload.told_at, "another job leaves a claim that may still be telling"

    WorkflowRunEndService.new(run, job_id: "job-1").ended!
    assert run.reload.told_at, "the job its stopped worker left takes its claim back and tells"
    assert_nil run.telling_job_id
  end

  test "a job that breaks never gives back a claim another job holds" do
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    run = run!(failing)
    run.update_columns(told_at: nil, telling_job_id: "job-1")

    Conversation::Workflows.stubs(:moved!).raises(RuntimeError, "broke before claiming")
    assert_raises(RuntimeError) { WorkflowRunEndService.new(run, job_id: "job-2").ended! }
    assert_equal "job-1", run.reload.telling_job_id

    Conversation::Workflows.unstub(:moved!)
    @adapter.any_instance.stubs(:post_workflow_failure).raises(AdapterError::ServerError, "internal_error")
    run.update_columns(telling_job_id: nil)
    assert_raises(AdapterError::ServerError) { WorkflowRunEndService.new(run, job_id: "job-3").ended! }
    run.update_columns(telling_job_id: "job-1")
    Workflow::Run.find(run.id).release_telling!("job-3")
    assert_equal "job-1", run.reload.telling_job_id
  end

  test "the job that tells a run's end is run again when its worker is stopped" do
    assert WorkflowRunEndedJob.runs_again_when_interrupted
  end

  test "a failure notice whose team channel is gone is sent to whoever published the workflow" do
    workflow = failing
    workflow.update!(owner_team: catalog_entries(:platform_team))
    CatalogEntry.any_instance.stubs(:role_value).with(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL).returns("C0GONE")
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    sent = sequence("sent")
    @adapter.any_instance.expects(:post_workflow_failure).with(has_entries(channel_id: "C0GONE")).in_sequence(sent).raises(AdapterError::NotFound, "channel_not_found")
    @adapter.any_instance.expects(:post_workflow_failure).with(has_entries(channel_id: @alice.platform_user_id)).in_sequence(sent).returns({})

    assert run!(workflow).told_at
  end

  test "a failure notice with nowhere at all to go is left untold" do
    workflow = failing
    @alice.update_columns(platform_user_id: nil)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter.any_instance.expects(:post_workflow_failure).never

    assert_nil run!(workflow).told_at
  end

  test "a test run and a run another workflow started say nothing" do
    workflow = failing
    FirefightAi::WorkflowRepair.any_instance.expects(:suggest).never
    @adapter.any_instance.expects(:post_workflow_failure).never

    Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "error" => "The logs could not be read." })
    perform_enqueued_jobs { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
  end

  test "an all clear is one line when the run raised and posted nothing, and only when the workflow asks for it" do
    workflow = published("Quiet check", steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 0 } } ])
    @adapter.any_instance.expects(:post_workflow_all_clear).never
    run!(workflow)

    workflow.update!(all_clear: true)
    @adapter.any_instance.unstub(:post_workflow_all_clear)
    @adapter.any_instance.expects(:post_workflow_all_clear).with(has_entries(channel_id: @alice.platform_user_id)).returns({})
    run = run!(workflow)
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
  end
end
