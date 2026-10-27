require "test_helper"

class FirefightAi::PullRequestReviewerTest < ActiveSupport::TestCase
  setup do
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    @choice = FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")
  end

  test "its prompt covers ordinary review, the failure patterns with their real context, and a failure chain shown before each report" do
    prompt = FirefightAi::PullRequestReviewer.system_prompt

    [
      "two workers or two requests racing over the same row", "a feature flag that is off is no protection", "retries and waits that last too long",
      "Read the table's real size before calling it large", "Schema and code out of step, either way", "Something removed or renamed that is still in use",
      "only works when deployed in a set order", "These are a floor", "past incidents and postmortems", "Write its failure chain",
      "Report each problem with report_finding as soon as it is shown", "call finish_part", "agent_instructions"
    ].each { |rule| assert_includes prompt, rule }
    assert_includes prompt, FirefightAi::Evidence::RULE
    assert_includes prompt, FirefightAi::Copy::RULE
    assert_includes prompt, FirefightAi::Manual::THINKING
  end

  test "a small pull request is one part, and the files keep the order given" do
    parts = FirefightAi::PullRequestReviewer.parts([ [ "db/migrate/1.rb", diff("db/migrate/1.rb", 3) ], [ "app/a.rb", diff("app/a.rb", 3) ] ])

    assert_equal 1, parts.size
    assert_equal [ "db/migrate/1.rb", "app/a.rb" ], parts.first.paths
  end

  test "a large pull request is split into parts that each fit, and every line of every file is in exactly one part" do
    files = (1..12).map { |index| [ "app/file_#{index}.rb", diff("app/file_#{index}.rb", 40) ] }
    files << [ "app/huge.rb", diff("app/huge.rb", 400, hunks: 6) ]
    files << [ "app/one_hunk.rb", diff("app/one_hunk.rb", 900, hunks: 1) ]
    limit = 6_000

    parts = FirefightAi::PullRequestReviewer.parts(files, limit: limit)

    assert_operator parts.size, :>, 3
    parts.each { |part| assert_operator part.text.size, :<=, limit }
    files.each do |path, text|
      added = text.lines.select { |line| line.start_with?("+") && !line.start_with?("+++") }
      seen = parts.flat_map(&:pieces).select { |piece| piece.path == path }.flat_map { |piece| piece.text.lines.select { |line| line.start_with?("+") && !line.start_with?("+++") } }
      assert_equal added, seen, "#{path} lost or repeated lines"
    end
    huge = parts.flat_map(&:pieces).select { |piece| piece.path == "app/huge.rb" }
    assert_operator huge.size, :>, 1
    assert_equal "app/huge.rb (piece 1 of #{huge.size})", huge.first.label
    assert(huge.all? { |piece| piece.text.start_with?("diff --git a/app/huge.rb b/app/huge.rb") })
    assert_includes parts.flat_map(&:pieces).select { |piece| piece.path == "app/one_hunk.rb" }.last.text, "@@ continued from the hunk above @@"
  end

  test "the overview opens the chat once, cached, and a part is reviewed in a loop that ends on finish_part, counting what the review spent before it" do
    chat = mock("chat")
    llm = stub(messages: [])
    chat.stubs(:to_llm).returns(llm)
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.expects(:with_instructions).with(FirefightAi::PullRequestReviewer.system_prompt, cache_until_here: true)
    chat.expects(:add_message).with(role: :user, content: includes("## The pull request\nacme/api PR #7"), cache_until_here: true)
    reviewer = FirefightAi::PullRequestReviewer.new(@workspace, inferable: nil, choice: @choice)
    reviewer.open(chat, tools: [], overview: { "The pull request" => "acme/api PR #7" })

    part = FirefightAi::PullRequestReviewer.parts([ [ "app/a.rb", diff("app/a.rb", 2) ] ]).first
    chat.expects(:add_message).with(role: :user, content: all_of(includes("## Part 2 of 3"), includes("<tool_result tool=\"#{FirefightAi::PullRequestReviewer::FRAME_FILES}\" trust=\"untrusted\">\n- app/a.rb"), includes("<tool_result tool=\"#{FirefightAi::PullRequestReviewer::FRAME_DIFF}\"")))
    answered = -> { true }
    purse = FirefightAi::AgentLoop::Purse.new(5)
    budget = FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 50, turns_used: 10, spent_micros: 5)
    FirefightAi::AgentLoop.expects(:new).with do |**given|
      given[:answered] == answered && given[:purse] == purse && given[:budget] == budget && given[:memory] == chat && given[:purpose] == AiPurpose::CODE_REVIEW &&
        given[:inference][:feature] == FirefightAi::PullRequestReviewer::FEATURE && given[:inference][:prompt_version] == FirefightAi::PullRequestReviewer.prompt_version
    end.returns(stub(run: :outcome))

    assert_equal :outcome, reviewer.review_part(chat: chat, part: part, number: 2, total: 3, budget: budget, purse: purse, answered: answered)
  end

  test "a chat that holds the overview already is not opened again" do
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: [ stub(role: :user) ]))
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.stubs(:with_instructions)
    chat.expects(:add_message).never

    FirefightAi::PullRequestReviewer.new(@workspace, inferable: nil, choice: @choice).open(chat, tools: [], overview: { "x" => "y" })
  end

  private

  def diff(path, lines, hunks: 1)
    body = (1..hunks).map do |hunk|
      start = (hunk * 1000)
      "@@ -#{start},#{lines} +#{start},#{lines} @@ def method_#{hunk}\n#{(1..lines).map { |line| "+  added line #{hunk}-#{line} #{'x' * 20}\n" }.join}"
    end.join
    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n#{body}"
  end
end
