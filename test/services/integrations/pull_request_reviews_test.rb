require "test_helper"

module Integrations
  class PullRequestReviewsTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
      @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
    end

    test "GitHub says a review was asked of the App, a pull request opened, got new commits or merged, and a reply on a thread" do
      github = MapEventSources::Github
      asked = github.review_signals({ "action" => "review_requested", "repository" => { "full_name" => "acme/shop" },
                                      "pull_request" => { "number" => 4, "head" => { "sha" => "a" * 40 } },
                                      "requested_reviewer" => { "login" => "firefight-app[bot]", "id" => 9 }, "sender" => { "login" => "ada", "type" => "User" } },
                                    headers: { "x-github-event" => "pull_request" }).sole
      assert_equal [ PullRequestReviews::REQUESTED, "acme/shop", 4, "a" * 40, [ "firefight-app[bot]" ] ],
                   [ asked.kind, asked.repository, asked.number, asked.head_sha, asked.reviewers ]
      assert PullRequestReviews.asked?(@row, asked)

      opened = github.review_signals({ "action" => "opened", "repository" => { "full_name" => "acme/shop" }, "pull_request" => { "number" => 4, "draft" => true, "head" => { "sha" => "a" * 40 } } },
                                     headers: { "x-github-event" => "pull_request" }).sole
      assert_equal [ PullRequestReviews::OPENED, true ], [ opened.kind, opened.draft ]

      pushed = github.review_signals({ "action" => "synchronize", "repository" => { "full_name" => "acme/shop" }, "pull_request" => { "number" => 4, "head" => { "sha" => "b" * 40 } } },
                                     headers: { "x-github-event" => "pull_request" }).sole
      assert_equal [ PullRequestReviews::PUSHED, "b" * 40 ], [ pushed.kind, pushed.head_sha ]

      merged = github.review_signals({ "action" => "closed", "repository" => { "full_name" => "acme/shop" }, "pull_request" => { "number" => 4, "merged" => true } },
                                     headers: { "x-github-event" => "pull_request" }).sole
      assert_equal PullRequestReviews::MERGED, merged.kind

      reply = github.review_signals({ "action" => "created", "repository" => { "full_name" => "acme/shop" }, "pull_request" => { "number" => 4, "head" => { "sha" => "b" * 40 } },
                                      "comment" => { "id" => 88, "in_reply_to_id" => 31, "body" => "This is handled in the job", "user" => { "login" => "ada", "type" => "User" } } },
                                    headers: { "x-github-event" => "pull_request_review_comment" }).sole
      assert reply.reply?
      assert_equal [ "88", "31", true ], [ reply.comment, reply.thread, reply.person ]
      assert_not PullRequestReviews.asked?(@row, reply)

      ask = github.review_signals({ "action" => "created", "repository" => { "full_name" => "acme/shop" }, "issue" => { "number" => 4, "pull_request" => {} },
                                    "comment" => { "id" => 89, "body" => "@firefight-app review", "user" => { "login" => "ada", "type" => "User" } } },
                                  headers: { "x-github-event" => "issue_comment" }).sole
      assert PullRequestReviews.asked?(@row, ask)

      assert_empty github.review_signals({ "action" => "created", "repository" => { "full_name" => "acme/shop" }, "issue" => { "number" => 5 }, "comment" => { "id" => 1 } },
                                         headers: { "x-github-event" => "issue_comment" }), "a comment on an issue that is no pull request says nothing"
    end

    test "GitLab says a reviewer was added, a draft became ready, new commits arrived, and a reply in a thread" do
      gitlab = MapEventSources::Gitlab
      base = { "project" => { "path_with_namespace" => "acme/web" }, "user" => { "username" => "ada" } }
      updated = gitlab.review_signals(base.merge("object_attributes" => { "iid" => 7, "action" => "update", "oldrev" => "o" * 40, "last_commit" => { "id" => "n" * 40 } },
                                                 "changes" => { "reviewers" => { "previous" => [], "current" => [ { "username" => "firefight-bot", "id" => 42 } ] } }),
                                      headers: { "x-gitlab-event" => "Merge Request Hook" })
      assert_equal [ PullRequestReviews::PUSHED, PullRequestReviews::REQUESTED ], updated.map(&:kind)
      assert_equal %w[firefight-bot 42], updated.last.reviewers

      ready = gitlab.review_signals(base.merge("object_attributes" => { "iid" => 7, "action" => "update", "last_commit" => { "id" => "n" * 40 } },
                                               "changes" => { "draft" => { "previous" => true, "current" => false } }),
                                    headers: { "x-gitlab-event" => "Merge Request Hook" })
      assert_equal [ PullRequestReviews::OPENED ], ready.map(&:kind)

      note = gitlab.review_signals(base.merge("object_attributes" => { "id" => 900, "note" => "Done", "noteable_type" => "MergeRequest", "type" => "DiffNote", "discussion_id" => "abc123" },
                                              "merge_request" => { "iid" => 7, "last_commit" => { "id" => "n" * 40 } }),
                                   headers: { "x-gitlab-event" => "Note Hook" }).sole
      assert_equal [ "900", "abc123" ], [ note.comment, note.thread ]
    end

    test "Bitbucket says a pull request opened, moved and merged, each update naming its reviewers, and a reply names its parent" do
      bitbucket = MapEventSources::Bitbucket
      payload = { "repository" => { "full_name" => "acme/checkout" }, "actor" => { "account_id" => "a1", "type" => "user" },
                  "pullrequest" => { "id" => 4, "source" => { "commit" => { "hash" => "c" * 12 } }, "reviewers" => [ { "account_id" => "557058:ff", "nickname" => "firefight" } ] } }
      updated = bitbucket.review_signals(payload, headers: { "x-event-key" => "pullrequest:updated" })
      assert_equal [ PullRequestReviews::PUSHED, PullRequestReviews::REQUESTED ], updated.map(&:kind)
      assert_includes updated.last.reviewers, "557058:ff"

      assert_equal [ PullRequestReviews::MERGED ], bitbucket.review_signals(payload, headers: { "x-event-key" => "pullrequest:fulfilled" }).map(&:kind)

      reply = bitbucket.review_signals(payload.merge("comment" => { "id" => 12, "parent" => { "id" => 801 }, "content" => { "raw" => "Why?" } }),
                                       headers: { "x-event-key" => "pullrequest:comment_created" }).sole
      assert_equal [ "12", "801", "Why?" ], [ reply.comment, reply.thread, reply.body ]
      assert_includes MapEventSources::Bitbucket::EVENTS, "pullrequest:comment_created"
    end

    test "a repository is public unless the host says it is private, and one whose visibility cannot be read counts as public" do
      Rails.cache.clear
      Packs::Github.any_instance.stubs(:review_visibility).returns(PullRequestReviews::VISIBILITY_PRIVATE)
      assert_not PullRequestReviews.public?(@row, "acme/private")

      Packs::Github.any_instance.stubs(:review_visibility).returns(PullRequestReviews::VISIBILITY_PUBLIC)
      assert PullRequestReviews.public?(@row, "acme/open")

      Packs::Github.any_instance.stubs(:review_visibility).raises(GithubApp::Error, "GitHub answered 502")
      assert PullRequestReviews.public?(@row, "acme/unknown")
    end

    test "each host says how it reads visibility, whether it posts a review whole and what its markdown renders" do
      GithubApp.stubs(:installation_token).returns("ghs_token")
      GithubApp.stubs(:get).with("/repos/acme/shop", token: "ghs_token").returns("private" => true)
      assert_equal PullRequestReviews::VISIBILITY_PRIVATE, Packs::Github.new(@integration).review_visibility(@row, repository: "acme/shop")
      assert PullRequestReviews.atomic?(@integration)
      assert_equal({ collapses: true, hides: true }, PullRequestReviews.markup(@integration))

      bitbucket = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
      assert_not PullRequestReviews.atomic?(bitbucket)
      assert_equal({ collapses: false, hides: false }, PullRequestReviews.markup(bitbucket))
    end

    test "only an answer that the line cannot take a comment leaves a line comment out" do
      placed = GitlabApi::Error.new("GitLab answered 400: line_code can't be blank").tap { |error| error.http_status = 400 }
      down = GitlabApi::Error.new("GitLab answered 400: but said by a proxy")

      assert PullRequestReviews.unplaceable?(placed)
      assert_not PullRequestReviews.unplaceable?(down), "the status is read, never the words"
    end

    test "a call runs the connection's tool through the authorizer given, and refuses a tool switched off" do
      @integration.tools.create!(name: "comment_on_pull_request", description: "Comments.", enabled: false)

      error = assert_raises(PullRequestReviews::Refused) do
        PullRequestReviews.call!(@row, PullRequestReviews::COMMENT, authorize: ->(*) { flunk }, repository: "acme/shop", number: 4, body: "Hi")
      end
      assert_includes error.message, "switched off"
    end

    test "a refusal is for good only when the host answered a 4xx other than 429, or said the thing is not there" do
      status = ->(code) { Integrations::Error.new("answered #{code}").tap { |error| error.http_status = code } }
      wrapped_404 = begin
        begin
          raise GithubApp::NotFound, "GitHub: Not Found"
        rescue GithubApp::NotFound
          raise Integrations::Error, "GitHub has no review comment 701."
        end
      rescue Integrations::Error => error
        error
      end

      [ status.call(404), status.call(422), status.call(403), Integrations::Error.new("gone").extend(Integrations::NotFound), wrapped_404 ].each do |error|
        assert PullRequestReviews.refused_for_good?(error), error.message
      end

      temporary = [
        status.call(429), status.call(502), Integrations::Error.new("GitHub answered 502 with something that is not JSON").tap { |error| error.http_status = 502 },
        status.call(403).extend(Integrations::RateLimited), Integrations::Error.new("could not reach api.github.com (Errno::ECONNRESET)").extend(Integrations::Unreachable),
        Integrations::Error.new("could not reach api.github.com (Net::ReadTimeout)").extend(Integrations::TimedOut), Integrations::Error.new("no status"),
        PullRequestReviews::Stopped.new("comment_on_pull_request was not run."), PullRequestReviews::ToolOff.new("switched off"),
        Integrations::PolicyRefusal.new("a rule").tap { |error| error.http_status = 403 }, StandardError.new("not ours")
      ]
      temporary.each { |error| assert_not PullRequestReviews.refused_for_good?(error), error.message }
    end

    test "a host refusing a call that was never made, as an installation suspended or missing a permission, is Firefight's state and not the host's answer" do
      tool = @integration.tools.create!(name: "comment_on_pull_request", description: "Comments.", enabled: true, read_only: false)
      Installations.stubs(:refusal).with(@row, tool).returns("comment_on_pull_request was not run. The app is suspended. Tell the person.")

      error = assert_raises(PullRequestReviews::Stopped) do
        PullRequestReviews.call!(@row, PullRequestReviews::COMMENT, authorize: ->(*, &run) { run.call }, repository: "acme/shop", number: 4, body: "Hi")
      end
      assert_not_kind_of PullRequestReviews::Refused, error
      assert_not PullRequestReviews.refused_for_good?(error)
    end
  end
end
