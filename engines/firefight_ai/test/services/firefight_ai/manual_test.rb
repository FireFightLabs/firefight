require "test_helper"

# The manual teaches what a great SRE does and why. The hard limits are enforced in the app, so the instructions only
# teach, and what one tool needs is said by that tool.
class FirefightAi::ManualTest < ActiveSupport::TestCase
  HABITS = [
    "Understand before you act", "look for the evidence that would prove it wrong", "Reads are free, so read",
    "Ask a person only for what only a person knows", "Follow the evidence to its source", "Changes are deliberate",
    "Prefer the smallest change that stops the damage", "Verify, do not assume", "A change is done when a fresh read shows it worked",
    "Be honest about certainty", "Lead with the answer, then the evidence", "Link each claim to where you read it",
    "Propose the next useful step and ask before taking it when it changes something", "Respect the person's decision",
    "What done means"
  ].freeze

  def chat_prompt = FirefightAi::Responder.new(nil, inferable: nil).send(:template_text)

  def always_on
    { chat: chat_prompt, run: FirefightAi::Investigator.system_prompt, check: FirefightAi::Monitor.system_prompt,
      helper: FirefightAi::Helper.template_text }
  end

  test "the chat and the run carry every habit of the manual, and the chat its guarded changes" do
    [ chat_prompt, FirefightAi::Investigator.system_prompt ].each do |prompt|
      HABITS.each { |habit| assert_includes prompt, habit }
      assert_includes prompt, FirefightAi::Manual::PLAYBOOKS
      assert_includes prompt, FirefightAi::Manual::WRITING
    end
    assert_includes chat_prompt, FirefightAi::Manual::TOOLS
    assert_includes FirefightAi::Investigator.system_prompt, FirefightAi::Manual::RUN_TOOLS
  end

  test "a scheduled check and a helper think the same way and read their tools the same way" do
    [ FirefightAi::Monitor.system_prompt, FirefightAi::Helper.template_text ].each do |prompt|
      assert_includes prompt, FirefightAi::Manual::THINKING
      assert_includes prompt, FirefightAi::Manual::RUN_TOOLS
    end
    assert_includes FirefightAi::Monitor.system_prompt, FirefightAi::Manual::PLAYBOOKS
  end

  test "the manual names every playbook, and tells tool results and files apart from instructions" do
    FirefightAi::Manual::PLAYBOOK_NAMES.each { |name| assert_includes FirefightAi::Manual::PLAYBOOKS, name }
    always_on.each_value { |prompt| assert_includes prompt, FirefightAi::Evidence::RULE }
  end

  # A model fed only prohibitions becomes scared and stops knowing what to do.
  test "every always on prompt says what to do, with no rule that opens on never and no em dash or semicolon" do
    always_on.each do |which, prompt|
      assert_no_match(/(\A|[.:\-] )Never\b/, prompt, "#{which} opens a rule with never")
      assert_no_match(/[—;]/, prompt, "#{which} has an em dash or a semicolon")
    end
  end

  test "the chat prompt is about a page, not the old rule book" do
    assert_operator chat_prompt.split.size, :<, 900
  end

  test "the chat says how a reply ends a turn and what a cancelled card means, and nothing checks an answer after it is written" do
    assert_includes chat_prompt, "Your reply is what the person reads, and it ends your turn."
    assert_includes chat_prompt, "the person cancelled it on its card"
    assert_not FirefightAi::Responder.const_defined?(:CHECK)
  end
end
