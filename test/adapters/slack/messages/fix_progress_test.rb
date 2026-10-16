require "test_helper"

class Slack::Messages::FixProgressTest < ActiveSupport::TestCase
  include FixPlanTestHelper

  setup do
    @plan = build_fix_plan(workspaces(:slack_workspace_one))
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "the fix is a checklist of its steps by their short names, each with how it stands, and never the instructions or a tool's words" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete, = @plan.steps.to_a
    delete.update_columns(title: "Delete the WAF rule")
    delete.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING)
    delete.finish!(Investigation::RemediationStep::STATUS_DONE, result: "<!channel> deleted rule 123 from zone abc")

    plan_block = Slack::Messages::FixProgress.build(@plan.reload).first

    assert_equal [ "plan", "Applying the fix" ], plan_block.values_at(:type, :title)
    assert_equal [ [ "1. Delete the WAF rule", "complete" ], [ "2. A step for a person", "pending" ], [ "3. Open a pull request with the change", "pending" ] ],
                 plan_block[:tasks].map { |task| task.values_at(:title, :status) }
    assert_not_includes plan_block.to_json, "deleted rule 123"
    assert_not_includes plan_block.to_json, "dns.tf"
    assert_equal "Applying the fix: 1 of 3 steps done", Slack::Messages::FixProgress.fallback(@plan)
  end

  test "each status reads as Slack's task status: waiting is in progress, done complete, declined an error, not started pending" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    waiting, done, declined = @plan.steps.to_a
    waiting.update_columns(status: Investigation::RemediationStep::STATUS_WAITING_APPROVAL)
    done.update_columns(status: Investigation::RemediationStep::STATUS_DONE, done_by_id: @alice.id)
    declined.update_columns(status: Investigation::RemediationStep::STATUS_DECLINED, failure: "Bob declined it")

    tasks = Slack::Messages::FixProgress.build(@plan.reload).first[:tasks]

    assert_equal %w[in_progress complete error], tasks.pluck(:status)
    assert_equal [ "Waiting for approval", "Done by Alice Smith", "Couldn't open a pull request with the change: Bob declined it." ],
                 tasks.map { |task| (task[:details] || task[:output]).dig(:elements, 0, :elements, 0, :text) }
  end

  test "a failed step says why in plain words and offers Try again, which asks first and names who it runs as" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    code = @plan.steps.third
    code.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, result: "Integrations::Unavailable: docker exited 125",
                        failure: Investigation::RemediationStep::FAILURE_SANDBOX)
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_equal "Fix stopped: 1 of 3 steps failed", blocks.first[:title]
    retry_row = blocks.find { |block| block.dig(:accessory, :action_id) == Identifiers::FIX_STEP_RETRY }
    assert_equal "*3.* Open a pull request with the change", retry_row.dig(:text, :text)
    assert_equal "Couldn't open a pull request with the change: the code sandbox didn't start.", blocks.first[:tasks].third.dig(:output, :elements, 0, :elements, 0, :text)
    assert_equal [ code.id, "Try step 3 again?" ], [ retry_row.dig(:accessory, :value), retry_row.dig(:accessory, :confirm, :title, :text) ]
    assert_includes retry_row.dig(:accessory, :confirm, :text, :text), "as Alice Smith"
    assert_not_includes blocks.to_json, "docker exited"
  end

  test "a cancelled fix and one Halon applied under a rule offer no Try again" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TOOL_SAID)
    @plan.cancel!(by: workspace_memberships(:bob_workspace_one))

    assert_nil retry_button(@plan.reload)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED, applied_from: AbilityGateway::SOURCE_INVESTIGATION)
    assert_nil retry_button(@plan.reload)
  end

  test "a code change at work says how far it got in counts, never the files or commands its agent named" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    code = @plan.steps.third
    work = Chat::CodeFixProgress.start
    work.add("Edited app/models/rule.rb")
    work.changed!("app/models/rule.rb")
    code.update!(status: Investigation::RemediationStep::STATUS_RUNNING, progress: work.to_json)

    task = Slack::Messages::FixProgress.build(@plan.reload).first[:tasks].third

    assert_equal [ "in_progress", "Writing the change: 1 step, 1 file changed so far" ], [ task[:status], task.dig(:details, :elements, 0, :elements, 0, :text) ]
    assert_not_includes task.to_json, "rule.rb"
  end

  test "a person's step offers Mark done under the checklist, by its short name" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete, tell, = @plan.steps.to_a
    delete.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    tell.update_columns(title: "Tell <!channel> security")

    row = Slack::Messages::FixProgress.build(@plan.reload).find { |block| block.dig(:accessory, :action_id) == Identifiers::MARK_FIX_STEP_DONE }

    assert_equal "*2.* Tell &lt;!channel&gt; security", row.dig(:text, :text)
    assert_equal tell.id, row.dig(:accessory, :value)
  end

  test "a workspace without plan blocks gets the same checklist as text, marked by status" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TOOL_SAID)

    blocks = Slack::Messages::FixProgress.build(@plan.reload, rich: false)

    assert_equal [ ":hammer_and_wrench:  *Applying the fix*", "divider" ], [ blocks.first.dig(:text, :text), blocks.second[:type] ]
    assert_equal ":x: 1. Make the change through a connected tool  _Couldn't make the change through a connected tool: the tool reported an error._\n" \
                 ":white_circle: 2. A step for a person\n:white_circle: 3. Open a pull request with the change", blocks.third.dig(:text, :text)
  end

  test "a fix with more steps to act on than Slack takes sends the rest to the run page and stays inside fifty blocks" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    30.times do |index|
      @plan.steps.create!(position: index + 4, kind: Investigation::RemediationStep::KIND_MANUAL, description: "Check #{index}",
                          status: Investigation::RemediationStep::STATUS_APPROVED)
    end

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_operator blocks.size, :<=, 50
    assert_match(/more steps to act on, on the run page/, blocks.find { |block| block[:type] == "context" && block.dig(:elements, 0, :text).include?("run page") }.dig(:elements, 0, :text))
  end

  test "a fix that ended offers Undo fix, which asks first, and one still applying or already undone does not" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    assert_nil undo_button(@plan)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
    button = undo_button(@plan.reload)
    assert_equal [ Identifiers::UNDO_FIX, @plan.id, "Write the undo?" ], [ button[:action_id], button[:value], button.dig(:confirm, :title, :text) ]

    undo = @plan.propose_undo!("summary" => "Put it back", "steps" => [ { "kind" => "manual", "title" => "Re-add the rule", "description" => "Re-add the rule" } ])
    assert_nil undo_button(@plan.reload)
    written = Slack::Messages::InvestigationRun.undo(plan: undo)
    assert_equal [ ":leftwards_arrow_with_hook:  *How to undo it*", "divider" ], [ written.first.dig(:text, :text), written.second[:type] ]
    undo.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    assert_equal "Undoing the fix", Slack::Messages::FixProgress.build(undo.reload).first[:title]
  end

  test "a fix being applied offers Cancel, which asks first, and a cancelled one says who stopped it" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    cancel = buttons(@plan).find { |element| element[:action_id] == Identifiers::CANCEL_FIX }
    assert_equal [ "Cancel fix", "Cancel this fix?" ], [ cancel.dig(:text, :text), cancel.dig(:confirm, :title, :text) ]

    @plan.cancel!(by: workspace_memberships(:bob_workspace_one))
    blocks = Slack::Messages::FixProgress.build(@plan)
    assert_equal "Fix cancelled", blocks.first[:title]
    assert blocks.find { |block| block[:type] == "context" }.dig(:elements, 0, :text).start_with?("Cancelled by Bob")
  end

  test "how a fix ended is said plainly: applied, stopped with each failure, or cancelled" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.each { |step| step.update_columns(status: Investigation::RemediationStep::STATUS_DONE) }
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_APPLIED)
    applied = Slack::Messages::FixProgress.ended(@plan.reload)
    assert_equal [ ":white_check_mark:  *Fix applied*", "3 of 3 steps done." ], [ applied.first.dig(:text, :text), applied.third.dig(:text, :text) ]

    @plan.steps.third.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_SANDBOX)
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    stopped = Slack::Messages::FixProgress.ended(@plan.reload)
    assert_equal ":warning:  *Fix stopped: 1 of 3 steps failed*", stopped.first.dig(:text, :text)
    assert_equal "Couldn't open a pull request with the change: the code sandbox didn't start.\nTry again from the fix's checklist.", stopped.third.dig(:text, :text)
    assert_equal "Fix stopped: 1 of 3 steps failed.", Slack::Messages::FixProgress.ended_text(@plan)
  end

  test "an approved step asks to be run, with how things stand now, Run and Dismiss, and Ask again once its approval expired" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete = @plan.steps.first
    approval = @plan.finding.investigation.workspace.ability_approvals.create!(
      principal: @alice, principal_label: "Alice", action_key: "cloudflare.execute", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: @alice, held_for_run: true, run_expires_at: 1.hour.from_now
    )
    delete.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id)

    checking = Slack::Messages::FixProgress.build(@plan.reload)
    assert_includes checking.third.dig(:elements, 0, :text), "Halon is checking how things stand now"
    assert_equal [ Identifiers::FIX_STEP_DISMISS ], checking.fourth[:elements].map { |button| button[:action_id] }

    delete.reload.checked!(Chat::CurrentState::Report.new(state: "The rule is gone already.", change: Chat::CurrentState::DONE_ALREADY))
    ready = Slack::Messages::FixProgress.build(@plan.reload)
    assert_equal "Approved, waiting for someone to run it", ready.first[:tasks].first.dig(:details, :elements, 0, :elements, 0, :text)
    assert_includes ready.third.dig(:elements, 0, :text), "Alice Smith approved it. Run it now?\n*Now:* The rule is gone already.\n:warning: This looks done already."
    assert_equal [ Identifiers::FIX_STEP_RUN, Identifiers::FIX_STEP_DISMISS ], ready.fourth[:elements].map { |button| button[:action_id] }

    approval.update_columns(status: Ability::Approval::STATUS_EXPIRED)
    expired = Slack::Messages::FixProgress.build(@plan.reload)
    assert_includes expired.third.dig(:elements, 0, :text), "nobody ran it within the hour"
    assert_equal [ Identifiers::FIX_STEP_ASK_AGAIN, Identifiers::FIX_STEP_DISMISS ], expired.fourth[:elements].map { |button| button[:action_id] }
  end

  private

  def buttons(plan)
    Slack::Messages::FixProgress.build(plan).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }
  end

  def undo_button(plan) = buttons(plan).find { |element| element[:action_id] == Identifiers::UNDO_FIX }

  def retry_button(plan)
    Slack::Messages::FixProgress.build(plan).find { |block| block.dig(:accessory, :action_id) == Identifiers::FIX_STEP_RETRY }
  end
end
