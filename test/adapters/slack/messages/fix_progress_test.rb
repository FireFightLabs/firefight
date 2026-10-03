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

  test "a fix that ended offers Undo fix, which asks first, and one still applying or already undone does not" do
    @plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    assert_nil undo_button(@plan)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    FeatureFlags.enable!(@plan.finding.investigation.workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
    button = undo_button(@plan.reload)
    assert_equal [ Identifiers::UNDO_FIX, @plan.id, "Write the undo?" ], [ button[:action_id], button[:value], button.dig(:confirm, :title, :text) ]

    undo = @plan.propose_undo!("summary" => "Put it back", "steps" => [ { "kind" => "manual", "description" => "Re-add the rule" } ])
    assert_nil undo_button(@plan.reload)
    assert_equal "*How to undo it*", Slack::Messages::InvestigationRun.undo(plan: undo).first.dig(:text, :text).lines.first.strip
    assert_equal "Apply undo", Slack::Messages::InvestigationRun.undo(plan: undo).last.dig(:elements, 0, :text, :text) if undo.apply_blocked_reason.nil?
    undo.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_SLACK)
    assert Slack::Messages::FixProgress.build(undo.reload).first.dig(:text, :text).start_with?("*Undoing the fix*")
  end

  private

  def undo_button(plan)
    Slack::Messages::FixProgress.build(plan).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }
                                .find { |element| element[:action_id] == Identifiers::UNDO_FIX }
  end
end
