require "test_helper"

class Slack::Messages::OnCallTest < ActiveSupport::TestCase
  include OnCallTestHelper

  setup { alert_run_with_restart_fix }

  def texts(blocks) = blocks.flat_map { |block| [ block.dig(:text, :text), *Array(block[:elements]).map { |element| element[:text].is_a?(Hash) ? element[:text][:text] : element[:text] } ] }.compact.join("\n")

  test "acting names the fix, the rule and who set it, what Halon read, and how to undo each step" do
    note = Investigation::Unattended::Note.new(plan: @plan, acted: true, rules: [ restart_rule ], readings: [ "Halon read web just now." ])

    shown = texts(Slack::Messages::OnCall.unattended(note))

    assert_match "Halon acted on its own", shown
    assert_match "Applying the fix: Restart web", shown
    assert_match "Unattended rule: Restart web when the average of its 5xx responses over the last 10 minutes is above 50. Set by <@U12345678>. Halon read web just now.", shown
    assert_match "> Step 1: Nothing to undo, a restart keeps the version", shown
    assert_match "Undo fix", shown
    assert_equal "Halon acted on its own: Restart web", Slack::Messages::OnCall.unattended_fallback(note)
  end

  test "not acting says why and that the fix waits" do
    note = Investigation::Unattended::Note.new(plan: @plan, acted: false, rules: [ restart_rule ], reason: "The reading was low.")

    assert_match "The reading was low. The fix waits for someone to apply it.", texts(Slack::Messages::OnCall.unattended(note))
  end

  test "Halon not starting offers Investigate only when starting it by hand would work" do
    with = Slack::Messages::OnCall.held(incident: @incident, reason: "Ceiling spent.", rerun: true)
    without = Slack::Messages::OnCall.held(incident: @incident, reason: "No AI.", rerun: false)

    assert_equal Identifiers::START_INVESTIGATION, with.last.dig(:elements, 0, :action_id)
    assert_nil without.find { |block| block[:type] == "actions" }
  end
end
