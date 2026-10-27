require "test_helper"

class HalonPullRequestReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/Shop",
                                  name: "Shop", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    Integrations::GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
    sign_in(users(:alice), @workspace)
  end

  test "the page shows the setting, the repositories on the map, and how to ask on each code host" do
    get halon_pull_request_reviews_url, headers: inertia_headers

    assert_equal "halon/pull-request-reviews", JSON.parse(response.body)["component"]
    assert_equal "off", inertia_props.dig("settings", "pullRequestReviewsOnOpen")
    assert_equal [ "acme/shop" ], inertia_props.dig("settings", "repositories")
    assert_equal [ { "id" => @row.integration_id, "name" => "GitHub", "ask" => "@firefight-app review", "reviewer" => nil } ], inertia_props["hosts"]
    assert_equal %w[GitHub GitLab Bitbucket].sort, inertia_props["providers"].sort
  end

  test "reviewing every pull request, or the chosen ones, says so, and choosing none is refused with why" do
    patch halon_pull_request_reviews_url, params: { pull_request_reviews_on_open: "all" }
    assert_redirected_to halon_pull_request_reviews_path
    assert_equal "Halon now reviews every pull request when it opens.", flash[:notice]
    assert @workspace.reload.reviews_on_open?("any/thing")

    patch halon_pull_request_reviews_url, params: { pull_request_reviews_on_open: "chosen", pull_request_review_repositories: [ "Acme/Shop" ] }
    assert_equal "Halon now reviews every pull request when it opens in 1 repository.", flash[:notice]
    assert @workspace.reload.reviews_on_open?("acme/shop")
    assert_not @workspace.reviews_on_open?("acme/other")
    follow_redirect!

    patch halon_pull_request_reviews_url, params: { pull_request_reviews_on_open: "chosen", pull_request_review_repositories: [] }, as: :json
    assert_redirected_to halon_pull_request_reviews_path
    assert_nil flash[:notice]
    assert_equal [ "acme/shop" ], @workspace.reload.pull_request_review_repositories

    patch halon_pull_request_reviews_url, params: { pull_request_reviews_on_open: "off" }
    assert_equal "Halon now reviews a pull request only when someone asks.", flash[:notice]
    assert_equal [ "off", [ "acme/shop" ] ], @workspace.reload.values_at(:pull_request_reviews_on_open, :pull_request_review_repositories),
                 "the chosen repositories are kept, so choosing them again brings them back"
  end

  test "a member may not change which pull requests Halon reviews" do
    sign_in(users(:bob), @workspace)

    patch halon_pull_request_reviews_url, params: { pull_request_reviews_on_open: "all" }

    assert_equal "off", @workspace.reload.pull_request_reviews_on_open
  end
end
