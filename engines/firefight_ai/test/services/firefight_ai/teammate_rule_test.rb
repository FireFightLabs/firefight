require "test_helper"

# Seen in a real chat about a release whose webhook failed: a manual deploy reported as the goal met, a fix recommended
# with nothing behind it, a request across two systems carried out on the wrong one, and a run Halon started failing
# with nobody told.
class FirefightAi::TeammateRuleTest < ActiveSupport::TestCase
  RULES = [
    FirefightAi::TeammateRule::NEXT_STEP_RULE, FirefightAi::TeammateRule::EVIDENCE_FIX_RULE, FirefightAi::TeammateRule::STARTED_RULE
  ].freeze

  test "a chat holds every teammate rule" do
    prompt = FirefightAi::Responder.new(nil, inferable: nil).send(:template_text)

    RULES.each { |rule| assert_includes prompt, rule }
  end

  test "a run holds the rule that a fix needs evidence, and none of the rules about talking to a person" do
    prompt = FirefightAi::Investigator.system_prompt

    assert_includes prompt, FirefightAi::TeammateRule::EVIDENCE_FIX_RULE
    assert_not_includes prompt, FirefightAi::TeammateRule::NEXT_STEP_RULE
  end

  test "every answer ends with the next step and an offer, and nothing changes without a yes" do
    rule = FirefightAi::TeammateRule::NEXT_STEP_RULE

    assert_match "the most useful next step and an offer to take it", rule
    assert_match "Never change anything without the person's yes", rule
    assert_match "take a no or another suggestion as the plan", rule
    assert_match "\"The latest main\" means read the commit main is at", rule
  end

  test "a fix is recommended only from a result, and an unknown cause leads to the check that reveals it" do
    rule = FirefightAi::TeammateRule::EVIDENCE_FIX_RULE

    assert_match "Recommend a fix only when a result you read shows the cause", rule
    assert_match "the check that would reveal it", rule
    assert_match "never a fix to try", rule
  end

  test "what Halon starts is watched and its failure told" do
    assert_match "start a watch on it with its purpose", FirefightAi::TeammateRule::STARTED_RULE
    assert_match "when anything you started fails, say so with the reason", FirefightAi::TeammateRule::STARTED_RULE
  end

  # Seen in real chats, told "you do have access", Halon repeated the same wrong call and the same refusal.
  test "a refusal the person disputes is checked again in that turn, never repeated" do
    rule = FirefightAi::CannotRule::STALE_RULE

    assert_match "goes stale once the person disputes it, says they changed something", rule
    assert_match "look for the tool by name in every group", rule
    assert_match "Never repeat an earlier refusal without a fresh check in that turn", rule
    assert_includes FirefightAi::Responder.new(nil, inferable: nil).send(:template_text), rule
    assert_no_match(/[—;]/, rule)
  end

  test "the rules are written in Firefight's punctuation" do
    RULES.each { |rule| assert_no_match(/[—;]/, rule) }
  end
end
