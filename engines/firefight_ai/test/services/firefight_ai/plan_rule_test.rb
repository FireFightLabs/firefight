require "test_helper"

# Halon owns a request until it is verified. The plan replaced the rules that asked it to say the plan back and keep the
# goal in view, so a chat holds the plan's rules and a run, which talks to nobody, holds none of them.
class FirefightAi::PlanRuleTest < ActiveSupport::TestCase
  test "a chat holds every plan rule" do
    prompt = FirefightAi::Responder.new(nil, inferable: nil).send(:template_text)

    FirefightAi::PlanRule::RULES.each { |rule| assert_includes prompt, rule }
  end

  test "a run holds none of them" do
    prompt = FirefightAi::Investigator.system_prompt

    FirefightAi::PlanRule::RULES.each { |rule| assert_not_includes prompt, rule }
  end

  test "a request of more than one step gets a plan said in two lines, and only its changes ask" do
    rule = FirefightAi::PlanRule::PLAN_RULE

    assert_match "make_plan with the goal in the person's words", rule
    assert_match "Say the plan back in two short lines and start", rule
    assert_match "the plan itself never waits for a yes", rule
    assert_match "When the request could mean more than one thing, ask which first", rule
  end

  test "a change carries its undo before it runs and ends with a check against normal" do
    assert_match "Write each change's undo before it runs", FirefightAi::PlanRule::STEP_RULE
    assert_match "carry each one to its goal", FirefightAi::PlanRule::STEP_RULE
    assert_match "run_key_query, which compares each with normal", FirefightAi::PlanRule::CHECK_RULE
    assert_match "resource_status", FirefightAi::PlanRule::CHECK_RULE
  end

  test "a partial failure stops and offers retry or undo, and a finished plan reports with links and the next step" do
    assert_match "what is done, what failed and why, quoting the provider, and what has not started", FirefightAi::PlanRule::FAILURE_RULE
    assert_match "offer to retry or to undo", FirefightAi::PlanRule::FAILURE_RULE
    assert_match "the pages that show it", FirefightAi::PlanRule::REPORT_RULE
    assert_match "offer to take the next step", FirefightAi::PlanRule::REPORT_RULE
  end

  test "a later time waits for approval and reads how things stand when it comes" do
    assert_match "make the plan with run_at", FirefightAi::PlanRule::SCHEDULE_RULE
    assert_match "reads how things stand first", FirefightAi::PlanRule::SCHEDULE_RULE
    assert_match "A time inside a freeze is refused", FirefightAi::PlanRule::SCHEDULE_RULE
  end

  test "the rules are written in Firefight's punctuation" do
    FirefightAi::PlanRule::RULES.each { |rule| assert_no_match(/[—;]/, rule) }
  end
end
