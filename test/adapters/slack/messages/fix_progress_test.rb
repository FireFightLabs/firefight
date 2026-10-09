require "test_helper"

class Slack::Messages::FixProgressTest < ActiveSupport::TestCase
  include FixPlanTestHelper

  setup do
    @plan = build_fix_plan(workspaces(:slack_workspace_one))
  end

  test "each step says how it went, a tool's words are escaped and cut short, and only a person's step offers Mark done" do
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    delete, tell, code = @plan.steps.to_a
    delete.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING)
    delete.finish!(Investigation::RemediationStep::STATUS_DONE, result: "<!channel> deleted #{'x' * 400}")

    blocks = Slack::Messages::FixProgress.build(@plan)

    assert_equal "*Applying the fix* by Alice Smith. 1 of 3 steps done.", blocks.first.dig(:text, :text)
    first = blocks.second.dig(:text, :text)
    assert_includes first, "_Done_\n>&lt;!channel&gt; deleted"
    assert_operator first.length, :<, 400
    assert_nil blocks.second[:accessory]
    assert_equal [ Identifiers::MARK_FIX_STEP_DONE, tell.id ], [ blocks.third.dig(:accessory, :action_id), blocks.third.dig(:accessory, :value) ]
    assert_equal code.id, blocks.fourth.dig(:accessory, :value)
    assert_equal "Applying the fix: 1 of 3 steps done", Slack::Messages::FixProgress.fallback(@plan)
  end

  test "words the agent wrote are escaped, and a fix longer than Slack takes sends the rest to the run page" do
    @plan.steps.first.update_columns(description: "Tell <!channel> about <https://evil.example|this>")
    50.times { |index| @plan.steps.create!(position: index + 4, kind: Investigation::RemediationStep::KIND_MANUAL, description: "Check #{index}") }

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_includes blocks.second.dig(:text, :text), "Tell &lt;!channel&gt; about &lt;https://evil.example|this&gt;"
    assert_operator blocks.size, :<=, 50
    assert_equal "8 more steps on the run page.", blocks.last.dig(:elements, 0, :text)
  end

  test "approved steps take three blocks each, and the message still fits in Slack's fifty" do
    30.times do |index|
      @plan.steps.create!(position: index + 4, kind: Investigation::RemediationStep::KIND_MANUAL, description: "Check #{index}",
                          status: Investigation::RemediationStep::STATUS_APPROVED)
    end

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_operator blocks.size, :<=, 50
    shown = blocks.count { |block| block[:type] == "section" } - 1
    assert_equal "#{33 - shown} more steps on the run page.", blocks.find { |block| block[:type] == "context" && block.dig(:elements, 0, :text).include?("run page") }.dig(:elements, 0, :text)
  end

  test "a fix that ended offers Undo fix, which asks first, and one still applying or already undone does not" do
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    assert_nil undo_button(@plan)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
    button = undo_button(@plan.reload)
    assert_equal [ Identifiers::UNDO_FIX, @plan.id, "Write the undo?" ], [ button[:action_id], button[:value], button.dig(:confirm, :title, :text) ]

    undo = @plan.propose_undo!("summary" => "Put it back", "steps" => [ { "kind" => "manual", "description" => "Re-add the rule" } ])
    assert_nil undo_button(@plan.reload)
    written = Slack::Messages::InvestigationRun.undo(plan: undo)
    assert_equal [ ":leftwards_arrow_with_hook:  *How to undo it*", "divider" ], [ written.first.dig(:text, :text), written.second[:type] ]
    assert_not written.third.dig(:text, :text).include?("How to undo it"), "the title is not repeated in the body"
    assert_equal "Apply undo", Slack::Messages::InvestigationRun.undo(plan: undo).last.dig(:elements, 0, :text, :text) if undo.apply_blocked_reason.nil?
    undo.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    assert Slack::Messages::FixProgress.build(undo.reload).first.dig(:text, :text).start_with?("*Undoing the fix*")
  end

  test "a fix being applied offers Cancel, which asks first, and a cancelled one says who stopped it" do
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    cancel = Slack::Messages::FixProgress.build(@plan).flat_map { |block| block[:elements] || [] }.find { |element| element[:action_id] == Identifiers::CANCEL_FIX }
    assert_equal [ "Cancel fix", "Cancel this fix?" ], [ cancel.dig(:text, :text), cancel.dig(:confirm, :title, :text) ]

    @plan.cancel!(by: workspace_memberships(:bob_workspace_one))
    assert Slack::Messages::FixProgress.build(@plan).first.dig(:text, :text).start_with?("*Fix cancelled* by Bob")
  end

  private

  def undo_button(plan)
    Slack::Messages::FixProgress.build(plan).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }
                                .find { |element| element[:action_id] == Identifiers::UNDO_FIX }
  end

  test "an approved step asks to be run, with how things stand now, Run and Dismiss, and Ask again once its approval expired" do
    alice = workspace_memberships(:alice_workspace_one)
    @plan.apply!(by: alice, from: AbilityGateway::SOURCE_SLACK)
    delete = @plan.steps.first
    approval = @plan.finding.investigation.workspace.ability_approvals.create!(
      principal: alice, principal_label: "Alice", action_key: "cloudflare.execute", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: alice, held_for_run: true, run_expires_at: 1.hour.from_now
    )
    delete.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id)

    checking = Slack::Messages::FixProgress.build(@plan.reload)
    assert_includes checking.third.dig(:elements, 0, :text), "Halon is checking how things stand now"
    assert_equal [ Identifiers::FIX_STEP_DISMISS ], checking.fourth[:elements].map { |button| button[:action_id] }

    delete.reload.checked!(Chat::CurrentState::Report.new(state: "The rule is gone already.", change: Chat::CurrentState::DONE_ALREADY))
    ready = Slack::Messages::FixProgress.build(@plan.reload)
    assert_includes ready.second.dig(:text, :text), "_Approved, waiting for someone to run it_"
    assert_includes ready.third.dig(:elements, 0, :text), "Alice Smith approved it. Run it now?\n*Now:* The rule is gone already.\n:warning: This looks done already."
    assert_equal [ Identifiers::FIX_STEP_RUN, Identifiers::FIX_STEP_DISMISS ], ready.fourth[:elements].map { |button| button[:action_id] }

    approval.update_columns(status: Ability::Approval::STATUS_EXPIRED)
    expired = Slack::Messages::FixProgress.build(@plan.reload)
    assert_includes expired.third.dig(:elements, 0, :text), "nobody ran it within the hour"
    assert_equal [ Identifiers::FIX_STEP_ASK_AGAIN, Identifiers::FIX_STEP_DISMISS ], expired.fourth[:elements].map { |button| button[:action_id] }
  end
end
