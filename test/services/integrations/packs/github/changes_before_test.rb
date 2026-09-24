require "test_helper"

class Integrations::Packs::Github::ChangesBeforeTest < ActiveSupport::TestCase
  STARTED = Time.utc(2026, 9, 24, 14, 5)

  setup do
    installation([ repository("acme/checkout", "2026-09-24T13:00:00Z"), repository("acme/billing", "2026-09-20T09:00:00Z") ])
    api(merge_search_path, { "items" => [] })
    deployments("acme/checkout", [])
    deployments("acme/billing", [])
  end

  test "a deploy that touches a file in the stack trace ranks first, and says why" do
    deployments("acme/checkout", [ deployment(2, "newsha", "2026-09-24T13:00:00Z"), deployment(1, "oldsha", "2026-09-23T10:00:00Z") ])
    succeeded("acme/checkout", 2, "2026-09-24T13:02:00Z")
    succeeded("acme/checkout", 1, "2026-09-23T10:02:00Z")
    api("/repos/acme/checkout/compare/oldsha...newsha", {
      "status" => "ahead", "files" => [ { "filename" => "app/models/pool.rb" }, { "filename" => "config/database.yml" } ],
      "commits" => [ { "commit" => { "message" => "Lower the pool size" } } ]
    })
    api("/repos/acme/checkout/git/trees/main?recursive=1", { "tree" => [ { "path" => "app/models/pool.rb", "type" => "blob" } ] })
    api("/repos/acme/billing/git/trees/main?recursive=1", { "tree" => [] })
    Integrations::GithubApp.stubs(:blame).returns([])

    text = changes(paths: [ { "value" => "app/app/models/pool.rb", "line" => 42, "source" => "stack frame" } ])

    assert_includes text, "app/app/models/pool.rb:42 from the stack trace is app/models/pool.rb in acme/checkout"
    assert_match(%r{1\. acme/checkout deploy newsha .*Lower the pool size}, text)
    assert_includes text, "which the stack trace runs through; changes configuration"
    assert_includes text, "acme/checkout: newsha, from a deploy record (production"
  end

  test "a deploy to an older commit than the one before is named a rollback" do
    deployments("acme/checkout", [ deployment(2, "oldsha", "2026-09-24T13:00:00Z"), deployment(1, "newsha", "2026-09-23T10:00:00Z") ])
    succeeded("acme/checkout", 2, "2026-09-24T13:02:00Z")
    succeeded("acme/checkout", 1, "2026-09-23T10:02:00Z")
    api("/repos/acme/checkout/compare/newsha...oldsha", { "status" => "behind", "files" => [ { "filename" => "app/models/pool.rb" } ], "commits" => [] })

    text = changes(names: [ { "value" => "checkout", "source" => "alert" } ])

    assert_includes text, "is a rollback to an older commit"
    assert_includes text, "a rollback to an older commit)"
  end

  test "a change after it started is set apart, since it cannot have caused it" do
    deployments("acme/checkout", [ deployment(2, "latersha", "2026-09-24T14:30:00Z"), deployment(1, "oldsha", "2026-09-23T10:00:00Z") ])
    succeeded("acme/checkout", 2, "2026-09-24T14:31:00Z")
    succeeded("acme/checkout", 1, "2026-09-23T10:02:00Z")
    api("/repos/acme/checkout/compare/oldsha...latersha", { "status" => "ahead", "files" => [], "commits" => [] })

    text = changes(names: [ { "value" => "checkout", "source" => "alert" } ])

    assert_includes text, "After it started, so not a cause unless the start time is wrong"
    assert_includes text, "No deploy or merge in the window before it started"
  end

  test "with nothing changed anywhere, it says to look past code, and names the week before" do
    text = changes

    assert_includes text, "No deploy or merge in the window before it started. Look past code"
    assert_includes text, "acme/checkout: last push 2026-09-24T13:00:00Z"
    assert_includes text, "Config, feature flag and infrastructure changes made outside git are not checked."
  end

  test "a search GitHub refuses is named as not checked rather than read as nothing found" do
    Integrations::GithubApp.stubs(:get).with(merge_search_path, token: "t").raises(Integrations::GithubApp::Error, "GitHub: API rate limit exceeded")

    text = changes

    assert_includes text, "Commits by acme could not be searched: GitHub: API rate limit exceeded"
  end

  private

  def changes(paths: [], names: [])
    clues = { "started" => { "source" => "the first alert", "estimated" => false }, "repositories" => [], "names" => names,
              "paths" => paths, "error_texts" => [], "commits" => [] }
    Integrations::Packs::Github::ChangesBefore.new(token: "t", started: STARTED, window: 6.hours, clues: clues).text
  end

  def api(path, value)
    Integrations::GithubApp.stubs(:get).with(path, token: "t").returns(value)
  end

  def installation(repositories)
    api("/installation/repositories?page=1&per_page=100", { "total_count" => repositories.size, "repositories" => repositories })
  end

  def repository(name, pushed_at)
    { "full_name" => name, "default_branch" => "main", "pushed_at" => pushed_at,
      "owner" => { "login" => name.split("/").first, "type" => "Organization" } }
  end

  def merge_search_path
    format = Integrations::Packs::Github::ChangesBefore::SEARCH_TIME
    range = "#{(STARTED - 6.hours).strftime(format)}..#{STARTED.strftime(format)}"
    "/search/commits?#{{ 'q' => "org:acme committer-date:#{range}", 'per_page' => 100 }.to_query}"
  end

  def deployments(repository, list)
    api("/repos/#{repository}/deployments?per_page=#{Integrations::Packs::Github::ChangesBefore::DEPLOYMENT_CANDIDATES}", list)
  end

  def deployment(id, sha, created_at)
    { "id" => id, "sha" => sha, "environment" => "production", "created_at" => created_at, "creator" => { "login" => "deployer" } }
  end

  def succeeded(repository, id, at)
    api("/repos/#{repository}/deployments/#{id}/statuses?per_page=#{Integrations::GithubApp::DEPLOYMENT_STATUS_LIMIT}",
        [ { "state" => "success", "created_at" => at } ])
  end
end
