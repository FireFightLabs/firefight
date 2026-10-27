require "test_helper"

class HalonPullRequestReviewPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400, status: PullRequestReview::STATUS_DONE,
                                        risk: PullRequestReview::RISK_HIGH, risk_reason: "Checkout depends on it.")
    @resource = ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/api",
                                              name: "api", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    map_link = AppUrl.absolute(Rails.application.routes.url_helpers.resource_map_path(ResourceMap::PAGE_VIEW_PARAM => ResourceMap::VIEW_FOCUS,
                                                                                         ResourceMap::PAGE_RESOURCE_PARAM => @resource.id))
    @finding = @review.findings.create!(
      position: 1, fingerprint: "f" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: PullRequestReview::Finding::SEVERITY_MAJOR,
      effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: "Queue the retry for its backoff delay", why: "It waits five minutes, as in INC-012.",
      failure_chain: [ "The retry is queued with no wait" ], path: "app/jobs/retry_job.rb", line: 12,
      evidence: [ { "kind" => PullRequestReview::Finding::EVIDENCE_INCIDENT, "title" => "INC-012", "url" => "https://example.com/inc" },
                  { "kind" => PullRequestReview::Finding::EVIDENCE_MAP_RESOURCE, "title" => "acme/api", "url" => map_link } ]
    )
  end

  test "a member reads every finding in full, with the evidence behind it" do
    sign_in(users(:bob), @workspace)

    get halon_pull_request_review_url(@review), headers: inertia_headers

    assert_equal "halon/pull-request-review", JSON.parse(response.body)["component"]
    assert_equal [ "acme/api", 7, "High", "Checkout depends on it." ], inertia_props["review"].values_at("repository", "number", "risk", "riskReason")
    finding = inertia_props["findings"].sole
    assert_equal [ @finding.id, "It waits five minutes, as in INC-012.", [ "The retry is queued with no wait" ] ], finding.values_at("id", "why", "failureChain")
    assert_equal %w[INC-012 acme/api], finding["evidence"].map { |item| item["title"] }
  end

  test "a resource on the map the viewer cannot reach is left out of what they see" do
    sign_in(users(:bob), @workspace)
    ResourceMap::Resource.stubs(:visible_to).returns(ResourceMap::Resource.none)

    get halon_pull_request_review_url(@review), headers: inertia_headers

    assert_equal %w[INC-012], inertia_props["findings"].sole["evidence"].map { |item| item["title"] }
  end

  test "a review of another workspace, a rehearsal and someone signed out never see it" do
    other = PullRequestReview.create!(workspace: workspaces(:slack_workspace_two), repository: "acme/api", number: 7, head_sha: "b" * 40,
                                      trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
    rehearsal = PullRequestReview.create!(workspace: @workspace, repository: "acme/api", number: 8, head_sha: "c" * 40, rehearsal: true,
                                          trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)

    get halon_pull_request_review_url(@review)
    assert_response :redirect

    sign_in(users(:bob), @workspace)
    get halon_pull_request_review_url(other), headers: inertia_headers
    assert_response :not_found
    get halon_pull_request_review_url(rehearsal), headers: inertia_headers
    assert_response :not_found
  end
end
