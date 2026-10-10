require "test_helper"

class Conversation::BenchScoreTest < ActiveSupport::TestCase
  Verdict = FirefightAi::ReplayJudge::Verdict
  REACHED = FirefightAi::Schemas::ReplayVerdict::REACHED
  YES = FirefightAi::Schemas::ReplayVerdict::YES

  # Stands in for a replay's transcript, with only what the score reads.
  Transcript = Struct.new(:confirmations, :unneeded_confirmations, :called, :replies, :not_recorded, keyword_init: true) do
    def called?(name) = called.include?(name)

    def cites_any?(texts) = texts.any? { |text| replies.join.include?(text) }
  end

  test "a run that reached the outcome with its evidence, moved on, asked only for its change and kept to budget scores full marks" do
    score = score_of(transcript(confirmations: [ :change ], called: [ "start_watch" ], replies: [ "Run https://example.test/runs/4 failed." ]),
                     verdict(questions: 1), expect(calls: [ "start_watch" ], evidence: [ "runs/4" ]), spent_cents: 10)

    assert_equal [ 1.0, 1.0, 1.0, 1.0 ], score.to_h.values
    assert_equal 1.0, score.total
  end

  test "an outcome reached without citing what shows it is worth half" do
    score = score_of(transcript(replies: [ "It failed." ]), verdict, expect(evidence: [ "runs/4" ]))

    assert_equal 0.5, score.right
  end

  test "right is not scored when nobody wrote down the outcome, and the total is the mean of the rest" do
    score = score_of(transcript, verdict, expect(outcome: nil))

    assert_nil score.right
    assert_equal 1.0, score.total
  end

  test "moving forward counts the judge and the calls taking the next step means, and a call it should never reach" do
    score = score_of(transcript(called: [ "rollback" ]), verdict(moved_forward: FirefightAi::Schemas::ReplayVerdict::PARTLY),
                     expect(calls: [ "start_watch", "rollback" ], never_calls: [ "rollback" ]))

    assert_in_delta (0.5 + 0.5 + 0.0) / 3, score.moved_forward, 0.001
  end

  test "a confirmation for a read and a question it could have answered both count against asking only when needed" do
    score = score_of(transcript(confirmations: [ :read, :change ], unneeded_confirmations: [ :read ]), verdict(questions: 2, unneeded_questions: 1), expect)

    assert_equal 0.5, score.asked_when_needed
  end

  test "spending within the ceiling is full marks and twice it is half" do
    assert_equal 1.0, Conversation::BenchScore.cost(250_000, 25)
    assert_equal 0.5, Conversation::BenchScore.cost(500_000, 25)
  end

  test "notes say what took marks away without what any call was given" do
    call = Conversation::BenchTranscript::Call.new(name: "northflank_api_request", arguments: { "path" => "/secret" }, reads: true,
                                                   approval: Chat::APPROVAL_APPROVED, recorded: true, failed: false, result: "")
    notes = Conversation::BenchScore.notes(transcript: transcript(unneeded_confirmations: [ call ], not_recorded: 2), verdict: verdict(unneeded_questions: 1, questions: 1),
                                           expect: expect(calls: [ "start_watch" ], evidence: [ "runs/4" ]))

    assert_equal [
      "Asked the person to confirm northflank_api_request, a call that only read.",
      "Asked 1 question it could have answered itself.",
      "Never called start_watch.",
      "Cited none of the evidence a right answer links to.",
      "2 calls were not in the record, so the replay left it there."
    ], notes
    refute_match "/secret", notes.join
  end

  private

  def score_of(transcript, verdict, expect, spent_cents: 5)
    Conversation::BenchScore.of(transcript: transcript, verdict: verdict, expect: expect, spent_micros: spent_cents * FirefightAi::AgentLoop::MICROS_PER_CENT)
  end

  def transcript(confirmations: [], unneeded_confirmations: [], called: [], replies: [ "Done." ], not_recorded: 0)
    Transcript.new(confirmations: confirmations, unneeded_confirmations: unneeded_confirmations, called: called, replies: replies, not_recorded: not_recorded)
  end

  def verdict(outcome: REACHED, moved_forward: YES, questions: 0, unneeded_questions: 0)
    Verdict.new(outcome: outcome, moved_forward: moved_forward, questions: questions, unneeded_questions: unneeded_questions, reason: "")
  end

  def expect(outcome: "It fails", calls: [], never_calls: [], evidence: [])
    Conversation::BenchCase::Expect.new(outcome: outcome, next_step: "Watch it", evidence: evidence, calls: calls, never_calls: never_calls, max_cents: 25)
  end
end
