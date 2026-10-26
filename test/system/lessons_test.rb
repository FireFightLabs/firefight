require "application_system_test_case"

class LessonsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "an admin approves a lesson as strict from the Lessons tab, and it shows as approved" do
    Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", source: incidents(:active_critical_ws1),
                         state: Chat::Memory::STATE_UNCONFIRMED)

    visit memory_path(tab: MemoryController::TAB_LESSONS)
    assert_text "What incidents taught"
    within(:xpath, "//tr[.//p[text()='Checkout retries go up when the payment timeout changes']]") { click_button "Approve" }
    within("[role=dialog]") do
      find("#lesson-strict").click
      click_button "Approve"
    end

    assert_text "Approved the INC-001 lesson. Pull request reviews check it from now on, and fail a check on a pull request that goes against it."
    click_button "Approved"
    assert_text "Strict"
    assert_text "Reviews fail a check on a pull request that goes against it."
  end

  test "a pull request a strict lesson holds is overridden with a reason from the link its check opens" do
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", source: incidents(:active_critical_ws1),
                                  state: Chat::Memory::STATE_UNCONFIRMED)
    lesson.approve!(by: @admin, strict: true)
    review = PullRequestReview.create!(workspace: @workspace, repository: "acme/checkout", number: 412, head_sha: "a" * 40, title: "Raise the payment timeout",
                                       url: "https://github.com/acme/checkout/pull/412", trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
    review.findings.create!(position: 1, fingerprint: "f" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY,
                            severity: PullRequestReview::Finding::SEVERITY_MAJOR, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN,
                            claim: "Raising the payment timeout makes checkout retry more", why: "Retries go up.", lesson: lesson)

    visit memory_path(tab: MemoryController::TAB_LESSONS, review: review.id)
    assert_text "Pull requests held by strict lessons"
    assert_text "Failing"
    click_button "Override"
    within("[role=dialog]") do
      fill_in "Why", with: "Ships behind a flag that stays off"
      click_button "Override"
    end

    assert_text "Overrode the INC-001 lesson on #412 in acme/checkout. Its check passes once nothing else holds it."
    assert_text "Overridden by"
    assert_text "Ships behind a flag that stays off"
  end

  test "a service turns posting high risk pull requests in its channel off from its catalog entry" do
    catalog_types(:service_ws1).catalog_attribute_definitions.create!(name: "Repository", slug: "repository", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
                                                                      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9)
    entry = catalog_entries(:auth_service)

    visit catalogue_type_path(catalog_types(:service_ws1).slug, CatalogEntry::QUERY_PARAM => entry.id)
    assert_text "Post high risk pull requests"
    find("#review-alerts").click

    assert_text "High risk pull requests no longer post in Auth Service's channel."
    assert_not entry.reload.review_alerts
    assert_equal "false", find("#review-alerts")["aria-checked"]
  end
end
