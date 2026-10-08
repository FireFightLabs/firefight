require "test_helper"

class Chat::CodeFixProgressTest < ActiveSupport::TestCase
  test "what is kept reads back the same, so a reload shows what arrived live" do
    work = Chat::CodeFixProgress.start(at: Time.zone.parse("2026-10-07 10:00:00"))
    work.live!
    work.add("Read app/models/pool.rb")
    work.add("Ran bin/rails test", result: Chat::CodeFixProgress::RESULT_PASSED)
    work.changed!("config/database.yml")
    work.tested!("bin/rails test", passed: true)
    work.opened!(files: { "config/database.yml" => [ 1, 1 ], "logo.png" => [ nil, nil ] }, pull_request: "https://github.com/acme/api/pull/7",
                 at: Time.zone.parse("2026-10-07 10:06:00"))

    again = Chat::CodeFixProgress.from_json(work.to_json)

    assert_equal work.to_h, again.to_h
    assert again.finished?
    assert_equal [ nil, nil ], [ again.files.last.added, again.files.last.removed ]
  end

  test "only the newest lines are kept, every one is counted, and a line never carries a secret" do
    work = Chat::CodeFixProgress.start
    (Chat::CodeFixProgress::LINES_KEPT + 5).times { |number| work.add("Read file#{number}.rb") }
    work.add("Ran curl -H 'Authorization: Bearer ghp_#{'b' * 36}'")

    assert_equal Chat::CodeFixProgress::LINES_KEPT, work.lines.size
    assert_equal Chat::CodeFixProgress::LINES_KEPT + 6, work.total
    assert_equal "Read file6.rb", work.lines.first.text
    assert_includes work.lines.last.text, "[REDACTED:github_token]"
  end

  test "the headline is the latest thing it did and how far it got, short enough for Slack" do
    work = Chat::CodeFixProgress.start
    work.add("Edited config/routes.rb")
    work.changed!("config/routes.rb")
    work.tested!("bin/rails test", passed: false)

    assert_equal "Edited config/routes.rb · 1 step · 1 file changed · tests failed", work.headline
    work.add("Ran #{'x' * 400}")
    assert_operator work.headline.size, :<=, Chat::CodeFixProgress::HEADLINE_LIMIT

    work.failed!("The coding agent did not finish in 15 minutes.\nmore detail")
    assert work.headline.start_with?("Stopped: The coding agent did not finish in 15 minutes. · ")
  end

  test "news is passed on at most once an interval, never twice the same, and the end always" do
    pace = Chat::CodeFixProgress::Pace.new(every: 5)
    work = Chat::CodeFixProgress.start

    assert pace.due?("step", work, now: 0)
    refute pace.due?("step", work, now: 10), "nothing new"
    work.add("Read a.rb")
    refute pace.due?("step", work, now: 2), "too soon"
    assert pace.due?("step", work, now: 6), "held back news goes once the interval passed"
    assert pace.due?("other", work, now: 6), "each step keeps its own pace"
    work.add("Read b.rb")
    work.failed!("Stopped")
    assert pace.due?("step", work, now: 7), "the end goes at once"
  end

  test "the agent waiting again and again for its answer is one line that says how long so far" do
    asked = Time.zone.parse("2026-10-09 10:00:00")
    work = Chat::CodeFixProgress.start(at: asked)
    work.add("Asked a question", at: asked)
    work.waited!(asked, at: asked + 30.seconds)
    work.waited!(asked, at: asked + 70.seconds)
    work.waited!(asked, at: asked + 130.seconds)

    assert_equal [ "Asked a question", "Waiting for your answer, 2m" ], work.lines.map(&:text)
    work.add("Edited release.yml")
    work.waited!(asked, at: asked + 200.seconds)
    assert_equal "Waiting for your answer, 3m", work.lines.last.text
    assert_equal 4, work.lines.size, "a wait after other work is a line of its own"
  end
end
