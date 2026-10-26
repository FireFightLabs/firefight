require "test_helper"

class PullRequestReview::StrictCheckTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @review = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
    @strict = lesson("Checkout retries go up when the payment timeout changes", strict: true)
  end

  test "a review no strict lesson touched sets no check, and a lesson that only comments never fails one" do
    finding(lesson: lesson("Deploys happen from main", strict: false))

    assert_nil @review.check_due
  end

  test "an open finding from a strict lesson fails the check, naming the lesson, and fixing it passes the check" do
    held = finding(lesson: @strict)

    assert_equal PullRequestReview::CHECK_FAILING, @review.check_due
    assert_equal "1 finding from a strict lesson is open: Lesson from INC-001.", @review.check_words(PullRequestReview::CHECK_FAILING)
    assert_equal "Lesson from INC-001", held.lesson_label

    held.fixed!("b" * 40)
    assert_equal PullRequestReview::CHECK_PASSING, @review.check_due
  end

  test "an override says why and who, passes the check once nothing else holds it, and lands once" do
    held = finding(lesson: @strict)

    assert_not held.override!(by: @admin, reason: "")
    assert held.override!(by: @admin, reason: "Behind a flag that stays off")
    assert_not held.override!(by: @admin, reason: "Again")

    assert_equal [ @admin, "Behind a flag that stays off" ], [ held.overridden_by, held.override_reason ]
    assert_equal "#{@admin.display_name} overrode it already.", held.override_blocked_reason
    assert_equal PullRequestReview::CHECK_PASSING, @review.check_due
  end

  test "a lesson made a comment since stops holding the check it failed" do
    held = finding(lesson: @strict)
    @review.claim_check!(PullRequestReview::CHECK_FAILING, @review.head_sha)

    @strict.edit_lesson!(by: @admin, text: @strict.text, strict: false)
    assert_not held.reload.holding?
    assert_equal PullRequestReview::CHECK_PASSING, @review.check_due
    assert_equal "Only a finding from a strict lesson holds a check.", held.override_blocked_reason
  end

  test "the same state on the same commit is claimed once, and a refusal lets the next change try again" do
    assert @review.claim_check!(PullRequestReview::CHECK_FAILING, "a" * 40)
    assert_not @review.claim_check!(PullRequestReview::CHECK_FAILING, "a" * 40)
    assert @review.claim_check!(PullRequestReview::CHECK_FAILING, "b" * 40)

    @review.check_failed!("GitHub answered 403")
    assert_equal [ nil, "GitHub answered 403" ], [ @review.check_state, @review.check_error ]
    assert @review.claim_check!(PullRequestReview::CHECK_FAILING, "b" * 40)
  end

  test "a change to an approved lesson names the reviews its open findings hold, after it commits" do
    finding(lesson: @strict)
    said = []
    subscriber = ActiveSupport::Notifications.subscribe(Chat::Memory::Lesson::EVENT) { |event| said << event.payload[:review_ids] }

    @strict.turn_down!(by: @admin, reason: "One off")

    assert_equal [ [ @review.id ] ], said
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "a review hands the model the approved lessons about the services owning its repository first, and only those can be cited" do
    catalog_types(:service_ws1).catalog_attribute_definitions.create!(name: "Code", slug: "code", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
                                                                      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9)
    auth = catalog_entries(:auth_service)
    auth.update!(attributes: auth.entry_attributes.merge("code" => "Acme/API"))
    about = lesson("Auth Service keeps sessions in Redis", strict: false, subject: auth)
    unapproved = Chat::Memory.create!(workspace: @workspace, text: "Not approved", source: incidents(:active_critical_ws1), state: Chat::Memory::STATE_UNCONFIRMED)

    assert_equal [ about, @strict ], @review.lessons_to_check
    assert_equal "#{about.id} (lesson from INC-001, about Auth Service): Auth Service keeps sessions in Redis", @review.lesson_lines.first
    assert_includes @review.lesson_lines.second, "strict"
    assert_equal @strict, @review.lesson_cited(@strict.id)
    assert_nil @review.lesson_cited(unapproved.id)
  end

  private

  def lesson(text, strict:, subject: nil)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, source: incidents(:active_critical_ws1), state: Chat::Memory::STATE_UNCONFIRMED)
                .tap { |memory| memory.approve!(by: @admin, strict: strict) }
  end

  def finding(lesson:, claim: "Raises the payment timeout")
    @review.findings.create!(
      position: @review.next_position, fingerprint: PullRequestReview::Finding.fingerprint_for(path: "app/a.rb", category: "stability", claim: claim),
      category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: PullRequestReview::Finding::SEVERITY_MAJOR,
      effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: claim, why: "Retries go up.", path: "app/a.rb", line: 3, lesson: lesson
    )
  end
end
