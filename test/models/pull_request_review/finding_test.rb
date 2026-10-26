require "test_helper"

class PullRequestReview::FindingTest < ActiveSupport::TestCase
  setup do
    @review = PullRequestReview.create!(workspace: workspaces(:slack_workspace_one), repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
  end

  test "a finding leads with its category, severity and effort, and is announced once written" do
    announced = capture_announcements { @finding = create_finding }

    assert_equal "Stability & Availability | Major | Quick win", @finding.header
    assert_equal [ [ @review.id, @finding.id, PullRequestReview::CHANGE_FINDING_ADDED ] ], announced
  end

  test "evidence must name its kind and title" do
    finding = build_finding(evidence: [ { "kind" => "rumour", "title" => "Someone said" } ])

    assert_not finding.valid?
    assert finding.errors.of_kind?(:evidence, :invalid) || finding.errors[:evidence].any?
  end

  test "the same problem in the same place has the same fingerprint whatever its words' case and punctuation" do
    one = PullRequestReview::Finding.fingerprint_for(path: "app/a.rb", category: "stability", claim: "Lock the draft first.")
    two = PullRequestReview::Finding.fingerprint_for(path: "app/a.rb", category: "stability", claim: "lock the draft first")

    assert_equal one, two
    assert_not_equal one, PullRequestReview::Finding.fingerprint_for(path: "app/b.rb", category: "stability", claim: "Lock the draft first.")
  end

  test "withdrawn says why and which finding showed it, once, and is announced as withdrawn" do
    finding = create_finding
    later = create_finding(claim: "Another problem", position: 2)
    announced = capture_announcements { assert finding.withdraw!("The guard above already handles it.", by: later) }

    assert_not finding.withdraw!("Again")
    assert_equal PullRequestReview::Finding::STATUS_WITHDRAWN, finding.status
    assert_equal "The guard above already handles it.", finding.withdrawn_reason
    assert_equal [ PullRequestReview::Finding::CROSS_CHECK_WITHDRAWN, later.id ], finding.cross_checks.sole.values_at("outcome", "finding_id")
    assert_equal [ PullRequestReview::CHANGE_FINDING_WITHDRAWN ], announced.map(&:last)
  end

  test "a strengthened finding keeps what the later check said and is announced as changed" do
    finding = create_finding
    later = create_finding(claim: "Another problem", position: 2)
    announced = capture_announcements { finding.strengthened!("The same retry loop runs in the worker too.", by: later, severity: PullRequestReview::Finding::SEVERITY_CRITICAL) }

    assert_equal PullRequestReview::Finding::SEVERITY_CRITICAL, finding.reload.severity
    assert_equal PullRequestReview::Finding::CROSS_CHECK_STRENGTHENED, finding.cross_checks.sole["outcome"]
    assert_equal [ PullRequestReview::CHANGE_FINDING_CHANGED ], announced.map(&:last)
  end

  test "a problem counts as prevented when it was major or serious and fixed before the pull request merged" do
    major = create_finding
    minor_serious = create_finding(claim: "Serious minor", position: 2, severity: PullRequestReview::Finding::SEVERITY_MINOR, serious: true)
    minor = create_finding(claim: "Minor", position: 3, severity: PullRequestReview::Finding::SEVERITY_MINOR)
    late = create_finding(claim: "Fixed after merge", position: 4)
    [ major, minor_serious, minor ].each { |finding| finding.fixed!("b" * 40, at: 2.hours.ago) }
    late.fixed!("c" * 40, at: 1.minute.ago)

    assert_empty PullRequestReview::Finding.prevented
    @review.merged!(1.hour.ago)

    assert_equal [ major, minor_serious ].map(&:id).sort, PullRequestReview::Finding.prevented.pluck(:id).sort
  end

  test "a rehearsal's findings never count as prevented" do
    @review.update!(rehearsal: true)
    create_finding.fixed!("b" * 40, at: 2.hours.ago)
    @review.merged!(1.hour.ago)

    assert_empty PullRequestReview::Finding.prevented
  end

  private

  def build_finding(claim: "Queue the retry for its backoff delay", position: 1, **attributes)
    @review.findings.build(
      position: position, fingerprint: PullRequestReview::Finding.fingerprint_for(path: "app/jobs/retry_job.rb", category: "stability", claim: claim),
      category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: PullRequestReview::Finding::SEVERITY_MAJOR,
      effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: claim, why: "It waits five minutes for the sweeper.",
      failure_chain: [ "The retry is queued with no wait", "The sweeper picks it up five minutes later" ],
      evidence: [ { "kind" => PullRequestReview::Finding::EVIDENCE_CODE, "title" => "app/jobs/retry_job.rb:12", "url" => "https://example.com/a" } ],
      path: "app/jobs/retry_job.rb", line: 12, **attributes
    )
  end

  def create_finding(**) = build_finding(**).tap(&:save!)

  def capture_announcements(&)
    announced = []
    subscriber = ActiveSupport::Notifications.subscribe(PullRequestReview::EVENT) do |event|
      announced << event.payload.values_at(:review_id, :finding_id, :change)
    end
    yield
    announced
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
