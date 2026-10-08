require "test_helper"

class FirefightAi::ChangeReviewerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @reviewer = FirefightAi::ChangeReviewer.new(@workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))
  end

  test "a change that sends what the other system never reads is wrong, and the diff reaches the model framed as evidence" do
    asked = nil
    stub_model(content: { does_what_was_asked: false, findings: [ "release.yml sends the commit in a body the deploy webhook ignores." ],
                          unverified: [], summary: "Sends the commit." }) { |text| asked = text }

    review = @reviewer.review(asked: "1. Send the tag", brief: "The webhook reads ref", evidence: nil, diff: "+ body: sha", checks: "- yaml: passed", said: "Done.")

    assert review.wrong?
    assert_equal [ "release.yml sends the commit in a body the deploy webhook ignores." ], review.findings
    assert_includes asked, "## What the person asked, oldest first\n1. Send the tag"
    assert_includes asked, "<tool_result tool=\"diff\" trust=\"untrusted\">\n+ body: sha"
    assert_includes asked, "## Evidence read before the change\n(none)"
  end

  test "a minor finding stands beside a change that does what was asked, and a wrong one always says why" do
    stub_model(content: { does_what_was_asked: true, findings: [ "No test covers it." ], unverified: [ "That ref holds the tag." ], summary: "Sends the tag." })
    review = @reviewer.review(asked: "", brief: "", evidence: "", diff: "", checks: "", said: "")
    assert_not review.wrong?
    assert_equal [ [ "No test covers it." ], [ "That ref holds the tag." ] ], [ review.findings, review.unverified ]

    stub_model(content: { does_what_was_asked: false, findings: [], unverified: [], summary: "Sends the commit." })
    assert_equal [ "It does not do what was asked. Sends the commit." ], @reviewer.review(asked: "", brief: "", evidence: "", diff: "", checks: "", said: "").findings
  end

  private

  def stub_model(content:, &seen)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    reply = llm_reply(content: content, input: 100, output: 20, cost: 0.0001)
    reply.stubs(:parsed).returns(content.deep_stringify_keys)
    chat.stubs(:ask).with { |text| seen&.call(text) || true }.returns(reply)
    RubyLLM.stubs(:chat).returns(chat)
  end
end
