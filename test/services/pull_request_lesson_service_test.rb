require "test_helper"

class PullRequestLessonServiceTest < ActiveSupport::TestCase
  Host = Integrations::ReviewHost
  Extractor = FirefightAi::PullRequestLessonExtractor

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @bob = workspace_memberships(:bob_workspace_one)
    @session = session!
    Integrations::PullRequestReviews.stubs(:identity).returns(Integrations::PullRequestReviews::Identity.new(handles: [ "firefight-app[bot]" ]))
    Host.stubs(:pull_request).returns(stub(title: "Raise the payment timeout"))
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([])
  end

  test "a pull request merged as Halon wrote it was accepted and teaches nothing" do
    outcome!(Host::STATE_MERGED, commits: [ halon_commit("a1"), base_merge("a2") ])
    Extractor.any_instance.expects(:extract).never

    assert_nil service.learn!
    assert_nil @session.reload.pull_request_outcome
    assert @session.pull_request_lesson_read_at
  end

  test "an edit a person made before merging is read with what they wrote and changed, and its lesson waits for approval" do
    outcome!(Host::STATE_MERGED, commits: [ halon_commit("a1"), person_commit("b1", "Add the index concurrently, orders is large") ])
    Host.expects(:changes_between).with(@row, repository: "acme/api", from: "a1", to: "b1").returns("diff --git a/db/x.rb b/db/x.rb\n+algorithm: :concurrently")
    Extractor.any_instance.expects(:extract).with { |handled:, earlier:, label:, **|
      handled.kind == Extractor::EDITED && handled.words.include?("Add the index concurrently") && handled.changes.include?("concurrently") &&
        earlier.empty? && label == "PR #12"
    }.returns(Extractor::Result.new(lesson: "Migrations in acme/api add indexes concurrently", basis: FirefightAi::Schemas::PullRequestLesson::STATED))

    lesson = service.learn!

    assert_equal [ "Migrations in acme/api add indexes concurrently", @session, Chat::Memory::Lesson::STATUS_WAITING ],
                 [ lesson.text, lesson.source, lesson.lesson_status ]
    assert_equal "PR #12", lesson.lesson_origin
    assert_equal CodeAgentSession::OUTCOME_EDITED, @session.reload.outcome_kind
    assert_nil service.learn!, "a pull request is read once"
  end

  test "a pull request closed by Halon itself, a bot or the host teaches nothing" do
    Extractor.any_instance.expects(:extract).never

    outcome!(Host::STATE_CLOSED, ended_by: "firefight-app[bot]")
    assert_nil service.learn!
    outcome!(Host::STATE_CLOSED, ended_by: "dependabot", person: false)
    assert_nil PullRequestLessonService.new(session!(number: 13)).learn!
    assert_nil @session.reload.pull_request_outcome
  end

  test "a close with no reason and nothing like it before is recorded but teaches nothing, and one that repeats is read against the earlier" do
    outcome!(Host::STATE_CLOSED)
    Extractor.any_instance.expects(:extract).once.with { |earlier:, handled:, **| earlier.map(&:label) == [ "PR #12" ] && handled.kind == Extractor::CLOSED }.returns(nil)

    assert_nil service.learn!
    assert_equal CodeAgentSession::OUTCOME_CLOSED, @session.reload.outcome_kind
    assert_nil PullRequestLessonService.new(session!(number: 13)).learn!
  end

  test "a reason the host keeps for closing it is what the person said" do
    outcome!(Host::STATE_CLOSED, reason: "We do not hand edit generated files")
    Extractor.any_instance.expects(:extract).with { |handled:, **| handled.words.include?("We do not hand edit generated files") }.returns(nil)

    service.learn!
  end

  test "a pull request still open is given back to be read once it ends" do
    outcome!(Host::STATE_OPEN)

    assert_nil service.learn!
    assert_nil @session.reload.pull_request_lesson_read_at
  end

  test "only whoever asked for the pull request or an admin may approve its lesson" do
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Generated files are never edited by hand", source: @session, state: Chat::Memory::STATE_UNCONFIRMED)
    other = Chat::Memory.create!(workspace: @workspace, text: "Another", source: session!(number: 14, principal: nil), state: Chat::Memory::STATE_UNCONFIRMED)

    assert_nil lesson.approve_blocked_reason(@bob)
    assert_equal "Only whoever asked for PR #14 in acme/api or a workspace admin can decide on its lessons.", other.approve_blocked_reason(@bob)
    assert lesson.approve!(by: @bob)
    assert_equal "Lesson from PR #12", PullRequestReview::Finding.new(lesson: lesson).lesson_label
  end

  private

  def service = PullRequestLessonService.new(@session)

  def session!(number: 12, principal: @bob)
    CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1, expires_at: 1.hour.from_now,
                             token_digest: SecureRandom.hex, principal: principal, integration_environment: @row, pull_request_number: number,
                             pull_request_url: "https://github.com/acme/api/pull/#{number}")
  end

  def outcome!(state, ended_by: "ada", person: true, reason: nil, commits: [])
    Host.stubs(:outcome).returns(Host::Outcome.new(state: state, ended_by: ended_by, ended_by_person: person, reason: reason, commits: commits, comments: []))
  end

  def halon_commit(sha) = Host::OutcomeCommit.new(sha: sha, author: "Halon", email: CodeAgentSession::COMMIT_EMAIL, message: "Raise the timeout")

  def person_commit(sha, message) = Host::OutcomeCommit.new(sha: sha, author: "ada", email: "ada@acme.test", message: message)

  def base_merge(sha) = Host::OutcomeCommit.new(sha: sha, author: "ada", email: "ada@acme.test", message: "Merge main", merge: true)
end
