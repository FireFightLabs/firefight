require "test_helper"

# Halon's small decisions made with RubyLLM::Judge where the deployment asks for it and the quick model answers
# judgments, and the structured way everywhere else, so the two can be compared on the bench.
class FirefightAi::JudgingTest < ActiveSupport::TestCase
  include FakeProviderHelper

  setup do
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @judge = FirefightAi::ModelChoice.new(model: "gpt-6-luna", provider: "openai", context: fake_provider_context(openai_api_key: "sk-test"))
  end

  test "structured is the default, and judge needs a quick model that answers judgments" do
    FirefightAi.stubs(:model_for).with(AiPurpose::SUMMARY, workspace: @workspace).returns(@judge)
    assert_nil FirefightAi::Judging.choice_for(@workspace)
    assert_equal @judge, FirefightAi::Judging.choice_for(@workspace, mode: FirefightAi::Configuration::JUDGMENT_JUDGE)

    haiku = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic")
    FirefightAi.stubs(:model_for).with(AiPurpose::SUMMARY, workspace: @workspace).returns(haiku)
    logged = []
    Rails.logger.stubs(:warn).with { |line| logged << line }
    assert_nil FirefightAi::Judging.choice_for(@workspace, mode: FirefightAi::Configuration::JUDGMENT_JUDGE)
    assert_nil FirefightAi::Judging.choice_for(@workspace, mode: FirefightAi::Configuration::JUDGMENT_JUDGE)
    assert_equal 1, logged.count { |line| JSON.parse(line)["event"] == FirefightAi::Judging::UNSUPPORTED_EVENT }, "said once per model"
  end

  test "an unknown mode is refused when the deployment boots" do
    configuration = FirefightAi::Configuration.new
    configuration.judgments = "judge"
    assert_equal FirefightAi::Configuration::JUDGMENT_JUDGE, configuration.judgments
    configuration.judgments = nil
    assert_equal FirefightAi::Configuration::JUDGMENT_STRUCTURED, configuration.judgments
    assert_raises(ArgumentError) { configuration.judgments = "vibes" }
  end

  test "each claim is judged by how likely its cited results show it, and a judgment is in the ledger" do
    FirefightAi.stubs(:model_for).with(AiPurpose::SUMMARY, workspace: @workspace).returns(@judge)
    answer_with({ model: "gpt-6-luna", answers: [ { probability: 0.92 }, { probability: 0.08 } ], usage: { input_tokens: 400, output_tokens: 4 } })

    verdicts = FirefightAi::CitationCheck.new(@workspace, inferable: @incident, judgments: FirefightAi::Configuration::JUDGMENT_JUDGE).check(claims: claims, sources: sources)

    assert_equal [ [ 1, true ], [ 2, false ] ], verdicts.map { |verdict| [ verdict.number, verdict.shown ] }
    assert_equal "Judged 8% likely that the cited results show it.", verdicts.last.reason
    sent = sent_requests.sole
    assert_match %r{/decisions\z}, sent[:url]
    assert_equal %w[claim_1 claim_2], sent[:body]["questions"].map { |question| question["name"] }
    assert_includes sent[:body]["input"], FirefightAi::Evidence.frame("github_fetch_file", "before_action :require_admin!", step: 3)
    row = Inference.find_by!(workspace: @workspace, prompt_template: FirefightAi::CitationCheck::JUDGMENT_TEMPLATE)
    assert_equal [ "gpt-6-luna", 400, 4, Inference::STATUS_SUCCESS ], [ row.model, row.input_tokens, row.output_tokens, row.status ]
  end

  test "a watch's state is the judge's choice when it is sure, and moves nothing when it is not" do
    FirefightAi.stubs(:model_for).with(AiPurpose::SUMMARY, workspace: @workspace).returns(@judge)
    watch = FirefightAi::WatchJudge.new(@workspace, judgments: FirefightAi::Configuration::JUDGMENT_JUDGE)
    described = { "state" => "running", "said" => "build running, 3 of 7 jobs done", "link" => "", "parts" => [] }

    answer_with(responses_text(described.to_json))
    answer_with(decision("done", 0.81))
    assert_equal FirefightAi::Schemas::WatchReading::DONE, reading(watch).state

    answer_with(responses_text(described.to_json))
    answer_with(decision("failed", 0.34))
    sure = reading(watch)
    assert_nil sure.state, "a judge not sure of any state moves nothing"
    assert_equal "build running, 3 of 7 jobs done", sure.said
  end

  test "a judgment that cannot be made this time leaves the structured answer's state" do
    FirefightAi.stubs(:model_for).with(AiPurpose::SUMMARY, workspace: @workspace).returns(@judge)
    watch = FirefightAi::WatchJudge.new(@workspace, judgments: FirefightAi::Configuration::JUDGMENT_JUDGE)
    answer_with(responses_text({ "state" => "running", "said" => "build running", "link" => "", "parts" => [] }.to_json))
    answer_with({ error: { message: "The server had an error" } }, status: 500)

    assert_equal FirefightAi::Schemas::WatchReading::RUNNING, reading(watch).state
  end

  private

  # A structured answer as OpenAI's Responses API sends it.
  def responses_text(text)
    { id: "resp_1", object: "response", status: "completed", model: "gpt-6-luna",
      output: [ { type: "message", role: "assistant", content: [ { type: "output_text", text: text } ] } ],
      usage: { input_tokens: 200, output_tokens: 30 } }
  end

  def reading(watch) = watch.reading(question: "Is the build done?", readings: [ [ Time.current, "build: running, 3 of 7 jobs done" ] ], so_far: "running")

  def decision(chosen, likely)
    others = FirefightAi::WatchJudge::STATE_OPTIONS.keys - [ chosen ]
    rest = (1 - likely) / others.size
    { model: "gpt-6-luna", answers: [ { choice: chosen, confidence: likely,
                                        probabilities: [ { value: chosen, probability: likely }, *others.map { |other| { value: other, probability: rest } } ] } ],
      usage: { input_tokens: 300, output_tokens: 3 } }
  end

  def claims
    [ FirefightAi::CitationCheck::Claim.new(number: 1, text: "The controller calls require_admin!", steps: [ 3 ]),
      FirefightAi::CitationCheck::Claim.new(number: 2, text: "The billing tables are missing in production", steps: [ 5 ]) ]
  end

  def sources
    [ FirefightAi::CitationCheck::Source.new(step: 3, tool: "github_fetch_file", text: "before_action :require_admin!"),
      FirefightAi::CitationCheck::Source.new(step: 5, tool: "planetscale_execute_read_query", text: "billing_schema_exists: true") ]
  end
end
