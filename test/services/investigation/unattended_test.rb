require "test_helper"

class Investigation::UnattendedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    @adapter = stub(post_fix_progress: { message_id: "1.2", channel_id: "C1" }, update_fix_progress: { success: true },
                    update_investigation_answer: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
  end

  test "a fix every change of which a rule allows is applied by Halon once a fresh reading is above the threshold, and the incident is told how to undo it" do
    rule = restart_rule
    grant_investigator(@api)
    Integrations::NativeExecutor.expects(:call).with { |tool:, **| tool == @metrics }.returns(metrics_answer([ 80, 120 ], [ 10, 20 ]))
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @api && arguments["path"] == "services/web-id/restart" }
                                .returns("content" => [ { "type" => "text", "text" => "Restarting" } ])
    @adapter.expects(:post_unattended_note).with do |channel_id:, thread_id:, note:|
      channel_id == @incident.channel_id && thread_id.nil? && note.acted && note.rules == [ rule ] && note.readings.first.include?("was 100 on web-0, above 50")
    end.returns(message_id: "9.9", channel_id: @incident.channel_id)

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::Unattended.consider!(@investigation) }

    step = @plan.steps.reload.sole
    assert @plan.reload.unattended?
    assert_equal [ "done", rule ], [ step.status, step.applied_under_rule ]
    assert_equal [ SystemAgent.investigator, AbilityGateway::SOURCE_INVESTIGATION ], [ step.invocation.principal, step.invocation.source ]
    assert_match "applied by Halon under the unattended rule: Restart web when the average of its 5xx responses", step.invocation.triggered_by_label
    assert_match "was 100 on web-0, above 50", @plan.unattended_reading
    assert_equal 1, rule.reload.usage_count
    reading = @workspace.ability_invocations.find_by!(action_key: @metrics.action_key, principal_id: SystemAgent.investigator.id)
    assert_match "Checking the unattended rule", reading.triggered_by_label
  end

  test "an approval rule that would hold the change is answered by the unattended rule, which the Approvals page names" do
    rule = restart_rule
    grant_investigator(@api)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool == @metrics }.returns(metrics_answer([ 90 ]))
    Integrations::NativeExecutor.expects(:call).with { |tool:, **| tool == @api }.returns("content" => [ { "type" => "text", "text" => "Restarting" } ])
    @adapter.stubs(:post_unattended_note).returns(message_id: "9.9", channel_id: "C1")
    AbilityApprovalNotificationJob.expects(:perform_later).never

    perform_enqueued_jobs(only: InvestigationFixJob, at: Time.current) { Investigation::Unattended.consider!(@investigation) }

    step = @plan.steps.reload.sole
    approval = @workspace.ability_approvals.find(step.invocation.approval_id)
    assert_equal "done", step.status
    assert_equal [ Ability::Approval::STATUS_APPROVED, rule ], [ approval.status, approval.approved_under_rule ]
    assert_equal "Unattended rule: #{rule.sentence}", approval.decider_name
    assert approval.consumed_at
  end

  test "a reading under the threshold leaves the fix for a person and says so under the run's answer" do
    restart_rule
    grant_investigator(@api)
    Integrations::NativeExecutor.expects(:call).with { |tool:, **| tool == @metrics }.returns(metrics_answer([ 10, 12 ]))
    @adapter.expects(:post_unattended_note).with do |thread_id:, note:, **|
      thread_id == "1.1" && !note.acted && note.reason.include?("was 11, not above 50")
    end.returns(message_id: "9.9", channel_id: "C1")

    assert_no_enqueued_jobs(only: InvestigationFixJob) { Investigation::Unattended.consider!(@investigation) }

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
    assert @plan.unattended_checked_at
  end

  test "Halon without a grant of the change does not act, and the incident is told what is missing" do
    restart_rule
    Integrations::NativeExecutor.expects(:call).never
    @adapter.expects(:post_unattended_note).with { |note:, **| !note.acted && note.reason.include?("holds no grant of Northflank's api_request") }
                                           .returns(message_id: "9.9", channel_id: "C1")

    Investigation::Unattended.consider!(@investigation)

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  test "a fix no rule touches is left as it is and nothing is said" do
    restart_rule(enabled: false)
    @adapter.expects(:post_unattended_note).never

    Investigation::Unattended.consider!(@investigation)

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  test "a run a person started, or one already looked at, is never applied on its own" do
    restart_rule
    grant_investigator(@api)
    @adapter.expects(:post_unattended_note).never
    @investigation.update_columns(trigger_source: Investigation::TRIGGER_DASHBOARD)

    Investigation::Unattended.consider!(@investigation)

    @investigation.update_columns(trigger_source: Investigation::TRIGGER_ALERT)
    @plan.update_columns(unattended_checked_at: Time.current)
    Investigation::Unattended.consider!(@investigation.reload)

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  test "a person who applied the fix first wins, and Halon does not apply it again" do
    restart_rule
    grant_investigator(@api)
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool == @metrics }.returns(metrics_answer([ 90 ]))
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_WEB)
    @adapter.expects(:post_unattended_note).never

    Investigation::Unattended.consider!(@investigation)

    assert_not @plan.reload.unattended?
  end

  test "a gateway call that names a rule is approved by it only for the step Halon is making under that rule now" do
    rule = restart_rule
    grant_investigator(@api)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    step = @plan.steps.sole
    arguments = step.call_arguments

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: @api.action_key, workspace: @workspace, params: arguments,
                                context: { source: AbilityGateway::SOURCE_INVESTIGATION, unattended_rule_id: rule.id })
    end

    @plan.apply_unattended!(rules: { step => rule }, reading: "read")
    step.reload.claim!(from: Investigation::RemediationStep::STATUS_PROPOSED, started_at: Time.current)
    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: @api.action_key, workspace: @workspace,
                                params: arguments.merge("path" => "services/web-id/delete"), context: { unattended_rule_id: rule.id })
    end
    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: workspace_memberships(:alice_workspace_one), action_key: @api.action_key, workspace: @workspace,
                                params: arguments, context: { unattended_rule_id: rule.id })
    end
    assert AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: @api.action_key, workspace: @workspace, params: arguments,
                                     context: { unattended_rule_id: rule.id })
  end

  test "a change a chat would wrap in a safeguard is left for a person, since nobody is there to answer it" do
    restart_rule
    grant_investigator(@api)
    Integrations::Mitigations.stubs(:call?).returns(true)
    Integrations::NativeExecutor.expects(:call).never
    @adapter.expects(:post_unattended_note).with { |note:, **| !note.acted && note.reason.include?("a person chooses how long before it is undone") }
                                           .returns(message_id: "9.9", channel_id: "C1")

    Investigation::Unattended.consider!(@investigation)

    assert_equal Investigation::RemediationPlan::STATUS_PROPOSED, @plan.reload.status
  end

  test "a rule whose change stops someone's work says Halon never makes it on its own" do
    rule = restart_rule
    grant_investigator(@api)
    Ability::Action.any_instance.stubs(:effect?).returns(false)
    Ability::Action.any_instance.stubs(:effect?).with(Ability::Action::EFFECT_STOPS).returns(true)

    assert_match "stops something someone started, and its owner is asked first", rule.blocked_reason
  end
end
