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

    assert_nil @review.commit_status_due
  end

  test "an open finding from a strict lesson fails the check, naming the lesson, and fixing it passes the check" do
    held = finding(lesson: @strict)

    assert_equal PullRequestReview::COMMIT_STATUS_FAILING, @review.commit_status_due
    assert_equal "1 finding from a strict lesson is open: Lesson from INC-001.", @review.commit_status_words(PullRequestReview::COMMIT_STATUS_FAILING)
    assert_equal "Lesson from INC-001", held.lesson_label

    held.fixed!("b" * 40)
    assert_equal PullRequestReview::COMMIT_STATUS_PASSING, @review.commit_status_due
  end

  test "a finding's comment names its lesson under the claim, linked to the incident, and says when a strict one holds the check" do
    held = finding(lesson: @strict)
    AppUrl.stubs(:root).returns("https://firefight.test")
    AppUrl.stubs(:absolute).returns("https://firefight.test/app/incidents/1")

    body = PullRequestReview::Comments.new.finding(held)

    assert_includes body, "Lesson from [INC-001](https://firefight.test/app/incidents/1): Checkout retries go up when the payment timeout changes. " \
                          "It is a strict lesson, so the Halon review check fails until this is fixed or someone overrides it."
    assert_operator body.index("Lesson from"), :<, body.index(held.why)
    assert_includes PullRequestReview::Comments.new.serious(held), "Lesson from"
    assert_not_includes PullRequestReview::Comments.new.finding(finding(lesson: nil, claim: "Another")), "Lesson from"
    public_body = PullRequestReview::Comments.new(evidence_page: "https://firefight.test/r").finding(held)
    assert_includes public_body, "From a lesson the team approved. It is a strict lesson"
    assert_not_includes public_body, "INC-001", "a public repository never sees which incident"
  end

  test "an override says why and who, passes the check once nothing else holds it, and lands once" do
    held = finding(lesson: @strict)

    assert_not held.override!(by: @admin, reason: "")
    assert held.override!(by: @admin, reason: "Behind a flag that stays off")
    assert_not held.override!(by: @admin, reason: "Again")

    assert_equal [ @admin, "Behind a flag that stays off" ], [ held.overridden_by, held.override_reason ]
    assert_equal "#{@admin.display_name} overrode it already.", held.override_blocked_reason(@admin)
    stale = PullRequestReview::Finding.find(held.id).tap { |each| each.overridden_at = nil }
    assert_not stale.override!(by: @admin, reason: "Mine too")
    assert_equal "#{@admin.display_name} overrode it already.", stale.override_state_blocked_reason, "the one who lost is told who won"
    assert_equal PullRequestReview::COMMIT_STATUS_PASSING, @review.commit_status_due
  end

  test "overriding is its own permission: admins and the owners of the pull request's services hold it, anyone else needs a grant" do
    held = finding(lesson: @strict)
    bob = workspace_memberships(:bob_workspace_one)
    refused = "Only a workspace admin, an owner of a service acme/api belongs to, or someone granted Override strict lessons can override it."

    assert_nil held.override_blocked_reason(@admin)
    assert_equal refused, held.override_blocked_reason(bob)

    catalog_types(:service_ws1).catalog_attribute_definitions.create!(name: "Code", slug: "code", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
                                                                      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9)
    service = catalog_entries(:auth_service)
    service.update!(attributes: service.entry_attributes.merge("code" => "acme/api"))
    team = catalog_entries(:platform_team)
    team.update!(attributes: team.entry_attributes.merge("members" => [ bob.id ]))
    assert_nil PullRequestReview.find(@review.id).findings.first.override_blocked_reason(bob), "an owner of the owning team's service may override"
    assert_not PullRequestReview::Finding.overrides_as_owner?(bob, {}), "never without the finding named"

    Ability::Grant.withhold!(workspace: @workspace, principal: bob, action: Ability::Action.lookup(Ability::Action::LESSON_OVERRIDE, @workspace))
    assert_equal refused, PullRequestReview.find(@review.id).findings.first.override_blocked_reason(bob), "No access takes the owner's default away"
    assert_equal WorkspaceMembership::DEFAULT_NO_ACCESS, bob.reload.default_access.find { |row| row.action&.key == Ability::Action::LESSON_OVERRIDE }.state
    bob.ability_grants.destroy_all

    team.update!(attributes: team.entry_attributes.merge("members" => []))
    Ability::Grant.grant!(workspace: @workspace, principal: bob, target: { action: Ability::Action.lookup(Ability::Action::LESSON_OVERRIDE, @workspace) })
    assert_nil PullRequestReview.find(@review.id).findings.first.override_blocked_reason(bob), "a grant lets anyone override"
  end

  test "overriding a strict lesson can be granted on the Permissions screen, and is never a create, read, update or delete column" do
    assert_includes Ability::Action.grantable_keys, Ability::Action::LESSON_OVERRIDE
    assert_equal "Override strict lessons", Ability::Action.described(Ability::Action::LESSON_OVERRIDE)[:title]
    assert_not Ability::Action::ACTIONS.include?(Ability::Action::ACTION_OVERRIDE)
  end

  test "a lesson made a comment since stops holding the check it failed" do
    held = finding(lesson: @strict)
    @review.claim_commit_status!(PullRequestReview::COMMIT_STATUS_FAILING, @review.head_sha)

    @strict.edit_lesson!(by: @admin, text: @strict.text, strict: false)
    assert_not held.reload.holding?
    assert_equal PullRequestReview::COMMIT_STATUS_PASSING, @review.commit_status_due
    assert_equal "Only a finding from a strict lesson holds a check.", held.override_blocked_reason(@admin)
  end

  test "a finding on an earlier head holds the newest head's check, the same problem found again counts once, and its override carries over" do
    held = finding(lesson: @strict)
    newer = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "b" * 40,
                                      trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400, status: PullRequestReview::STATUS_DONE)
    again = newer.findings.create!(position: 1, fingerprint: held.fingerprint, category: held.category, severity: held.severity, effort: held.effort,
                                   claim: held.claim, why: held.why, lesson: @strict)

    assert_equal PullRequestReview::COMMIT_STATUS_FAILING, newer.commit_status_due
    assert_equal "1 finding from a strict lesson is open: Lesson from INC-001.", newer.commit_status_words(PullRequestReview::COMMIT_STATUS_FAILING)

    held.override!(by: @admin, reason: "Behind a flag")
    again.override!(by: @admin, reason: "Behind a flag")
    third = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "c" * 40,
                                      trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400, status: PullRequestReview::STATUS_DONE)
    carried = third.findings.create!(position: 1, fingerprint: held.fingerprint, category: held.category, severity: held.severity, effort: held.effort,
                                     claim: held.claim, why: held.why, lesson: @strict)
    assert_equal [ @admin, "Behind a flag" ], [ carried.overridden_by, carried.override_reason ]
    assert_equal PullRequestReview::COMMIT_STATUS_PASSING, third.commit_status_due
  end

  test "the same state on the same commit is claimed once, and a refusal lets the next change try again" do
    assert @review.claim_commit_status!(PullRequestReview::COMMIT_STATUS_FAILING, "a" * 40)
    assert_not @review.claim_commit_status!(PullRequestReview::COMMIT_STATUS_FAILING, "a" * 40)
    assert @review.claim_commit_status!(PullRequestReview::COMMIT_STATUS_FAILING, "b" * 40)

    @review.commit_status_failed!("GitHub answered 403")
    assert_equal [ nil, "GitHub answered 403" ], [ @review.commit_status, @review.commit_status_error ]
    assert @review.claim_commit_status!(PullRequestReview::COMMIT_STATUS_FAILING, "b" * 40)
  end

  test "a change to an approved lesson announces each open finding it produced, after it commits, and expiry never reaches it" do
    held = finding(lesson: @strict)
    said = []
    subscriber = ActiveSupport::Notifications.subscribe(PullRequestReview::EVENT) { |event| said << event.payload.values_at(:finding_id, :change) }

    @strict.turn_down!(by: @admin, reason: "One off")
    assert_equal [ [ held.id, PullRequestReview::CHANGE_FINDING_CHANGED ] ], said

    expiring = lesson("Web runs three replicas", strict: true)
    other = finding(lesson: expiring, claim: "Scales web to one")
    expiring.update_columns(updated_at: 40.days.ago)
    said.clear
    @workspace.update!(memory_expiry_days: 30)
    assert_equal 0, Chat::Memory.expire!(@workspace)
    assert_empty said
    assert other.reload.holding?
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "overriding the newest copy of a problem overrides the open copies on earlier heads too, so the check passes" do
    older = finding(lesson: @strict)
    @review.update_columns(status: PullRequestReview::STATUS_DONE)
    newer_review = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "b" * 40,
                                             trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
    newer = newer_review.findings.create!(position: 1, fingerprint: older.fingerprint, category: older.category, severity: older.severity,
                                          effort: older.effort, claim: older.claim, why: older.why, lesson: @strict)

    assert newer.override!(by: @admin, reason: "Behind a flag")

    assert_equal [ @admin, "Behind a flag" ], [ older.reload.overridden_by, older.override_reason ]
    assert_equal PullRequestReview::COMMIT_STATUS_PASSING, newer_review.commit_status_due
  end

  test "on a public repository the check's words name no lesson" do
    finding(lesson: @strict)

    assert_equal "1 finding from a strict lesson is open.", @review.commit_status_words(PullRequestReview::COMMIT_STATUS_FAILING, public: true)
  end

  test "a review hands the model the approved lessons about the services owning its repository first, and only those can be cited" do
    catalog_types(:service_ws1).catalog_attribute_definitions.create!(name: "Code", slug: "code", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
                                                                      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9)
    auth = catalog_entries(:auth_service)
    auth.update!(attributes: auth.entry_attributes.merge("code" => "Acme/API"))
    about = lesson("Auth Service keeps sessions in Redis", strict: false, subject: auth)
    unapproved = Chat::Memory.create!(workspace: @workspace, text: "Not approved", source: incidents(:active_critical_ws1), state: Chat::Memory::STATE_UNCONFIRMED)

    reader = SystemAgent.investigator
    assert_equal [ about, @strict ], @review.lessons_to_check(reader)
    assert_equal "- #{about.id} (lesson from INC-001, about Auth Service): Auth Service keeps sessions in Redis", @review.lesson_lines(reader).first
    assert_includes @review.lesson_lines(reader).second, "strict"
    assert_equal @strict, @review.lesson_cited(" #{@strict.id} ", reader)
    assert_nil @review.lesson_cited(unapproved.id, reader)
    assert_includes PullRequestReview::Context.new(@review, reader).sections["Lessons the team approved"], "#{@strict.id} (lesson from INC-001, strict)"
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
