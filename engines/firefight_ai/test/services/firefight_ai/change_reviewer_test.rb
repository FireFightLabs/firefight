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

  test "a long diff shows the file the person named whole, fills the rest with whole files, and names every file left out" do
    named = file_diff(".github/workflows/release.yml", 30_000)
    others = (1..8).map { |index| file_diff("app/services/part_#{index}.rb", 9_000) }
    asked = nil
    stub_model(content: { does_what_was_asked: true, findings: [], verified: [ "The run name holds only hyphens." ], unverified: [], summary: "Fixes the name." }) { |text| asked = text }

    review = @reviewer.review(asked: "1. Fix the run name in release.yml", brief: "", evidence: "", diff: [ *others.first(4), named, *others.drop(4) ].join,
                              checks: "", said: "")

    assert_includes asked, named, "the file the change is about is never cut"
    assert_equal 5, review.unreviewed.size
    assert_includes asked, "## Files not shown, since the change is too large to review whole\n- #{review.unreviewed.first}"
    review.unreviewed.each { |path| assert_not_includes asked, "diff --git a/#{path} " }
    assert_equal [ "The run name holds only hyphens." ], review.verified
  end

  test "a long diff naming no file still reviews whole files and never cuts one" do
    parts = [ file_diff("a.rb", 70_000), file_diff("b.rb", 20_000) ]

    shown, left_out = FirefightAi::ChangeReviewer.shown(parts.join, named: "Fix it")

    assert_equal parts.last, shown
    assert_equal [ "a.rb" ], left_out
  end

  test "an update to an open pull request names the files it changed, and a short diff is shown whole" do
    asked = nil
    stub_model(content: { does_what_was_asked: true, findings: [], verified: [], unverified: [], summary: "Merges main." }) { |text| asked = text }

    review = @reviewer.review(asked: "", brief: "", evidence: "", diff: file_diff("release.yml", 100), checks: "", said: "", updated: [])

    assert_includes asked, "## Files this update changed\n(none of the pull request's files, only a merge)"
    assert_includes asked, "## The diff of the pull request against its base branch"
    assert_empty review.unreviewed
  end

  private

  def file_diff(path, size)
    header = "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n"
    "#{header}#{"+#{'x' * 99}\n" * ((size - header.size) / 101)}"
  end

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
