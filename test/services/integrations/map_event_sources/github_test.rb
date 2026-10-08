require "test_helper"

module Integrations
  module MapEventSources
    class GithubTest < ActiveSupport::TestCase
      SECRET = "app-webhook-secret".freeze

      test "a delivery signed with the App's secret is GitHub's, matching GitHub's own example, and one signed otherwise is not" do
        # The example in GitHub's docs (docs.github.com, Validating webhook deliveries, Testing the webhook payload validation).
        example = { "x-hub-signature-256" => "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17" }
        assert Github.verify(raw_body: "Hello, World!", headers: example, secret: "It's a Secret to Everybody")

        body = { "zen" => "Keep it logically awesome." }.to_json
        headers = signed(body)
        assert Github.verify(raw_body: body, headers: headers, secret: SECRET)
        assert_not Github.verify(raw_body: body, headers: headers, secret: "another secret")
        assert_not Github.verify(raw_body: body.sub("awesome", "plain"), headers: headers, secret: SECRET)
        assert_not Github.verify(raw_body: body, headers: { "x-hub-signature-256" => headers["x-hub-signature-256"].delete_prefix("sha256=") }, secret: SECRET)
        assert_not Github.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Github.verify(raw_body: body, headers: headers, secret: nil)
      end

      test "a delivery is about the installation it names" do
        assert_equal 42, Github.installation_of({ "installation" => { "id" => 42 } }, headers: {})
        assert_nil Github.installation_of({}, headers: {})
      end

      test "a push to the default branch that changes an infrastructure file re-reads its repository, and any other push nothing" do
        event = push_events({ "modified" => [ "infra/dns.tf" ] }).sole
        assert_equal [ "delivery-1", ResourceMap::Event::UPDATED ], [ event.id, event.action ]
        assert_equal ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web"), event.scope
        assert_equal 1, push_events({ "removed" => [ "charts/web/values.yaml" ] }).size, "removing a file changes what the files say too"

        assert_empty push_events({ "modified" => [ "src/app.ts", "README.md" ] }), "a push of application code changes nothing the map reads"
        assert_empty push_events({ "modified" => [ "infra/dns.tf" ] }, ref: "refs/heads/feature")
        assert_empty push_events({ "modified" => [ "infra/dns.tf" ] }, deleted: true)
        assert_equal 1, push_events(nil).size, "a push listing no commits, such as a force push back, may have changed any file"
        commits = Array.new(Github::MOST_COMMITS) { { "modified" => [ "src/app.ts" ] } }
        assert_equal 1, Github.events(push(commits), headers: headers_for("push")).size, "a push at GitHub's cap may have changed files it does not list"
      end

      test "a repository created, deleted, archived or given another default branch is read again, and one renamed or moved rescopes" do
        assert_equal [ ResourceMap::Event::ADDED ], repository("created").map(&:action)
        assert_equal [ ResourceMap::Event::REMOVED ], repository("deleted").map(&:action)
        assert_equal [ ResourceMap::Event::UPDATED ], repository("archived").map(&:action)
        assert_equal [ ResourceMap::Event::UPDATED ], repository("unarchived").map(&:action)
        assert_equal [ ResourceMap::Event::UPDATED ], repository("edited", "changes" => { "default_branch" => { "from" => "master" } }).map(&:action)
        assert_empty repository("edited", "changes" => { "description" => { "from" => "old" } })
        assert_empty repository("publicized")
        assert_empty repository("privatized")

        renamed = repository("renamed", "changes" => { "repository" => { "name" => { "from" => "old" } } }).sole
        assert renamed.rescope?
        assert renamed.scope.everything?
        assert repository("transferred").sole.rescope?
      end

      test "repositories added to the installation are read one by one, and one removed rescopes the connection" do
        added = Github.events({ "action" => "added", "repositories_added" => [ { "full_name" => "acme/web" }, { "full_name" => "acme/api" } ] },
                              headers: headers_for("installation_repositories"))
        assert_equal [ [ "delivery-1:acme/web", "acme/web" ], [ "delivery-1:acme/api", "acme/api" ] ], added.map { |event| [ event.id, event.scope.external_id ] }
        assert added.all? { |event| event.action == ResourceMap::Event::ADDED }

        removed = Github.events({ "action" => "removed", "repositories_removed" => [ { "full_name" => "acme/web" } ] }, headers: headers_for("installation_repositories"))
        assert removed.sole.rescope?
        assert_empty Github.events({ "action" => "opened" }, headers: headers_for("issues"))
      end

      test "a push, a pull request, a review and the checks on a branch each name what a followed pull request should read again" do
        repository = { "repository" => { "full_name" => "acme/web" } }
        nudge = ->(event, payload) { Github.pull_request_nudges(repository.merge(payload), headers: headers_for(event)).sole }

        assert_equal [ [], [ "main" ] ], nudge.call("push", "ref" => "refs/heads/main").then { |found| [ found.numbers, found.branches ] }
        assert_equal [ 689 ], nudge.call("pull_request", "action" => "synchronize", "pull_request" => { "number" => 689 }).numbers
        assert_equal [ 689 ], nudge.call("pull_request_review", "pull_request" => { "number" => 689 }).numbers
        suite = nudge.call("check_suite", "check_suite" => { "head_branch" => "halon/fix-1", "pull_requests" => [ { "number" => 689 } ] })
        assert_equal [ [ 689 ], [ "halon/fix-1" ] ], [ suite.numbers, suite.branches ]
        assert_equal [ "halon/fix-1" ], nudge.call("status", "branches" => [ { "name" => "halon/fix-1" } ]).branches
        assert_empty Github.pull_request_nudges(repository.merge("action" => "opened"), headers: headers_for("issues"))
      end

      private

      def signed(body) = { "x-hub-signature-256" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, body)}" }

      def headers_for(event) = { "x-github-event" => event, "x-github-delivery" => "delivery-1" }

      def push(commits, ref: "refs/heads/main", deleted: false)
        { "ref" => ref, "deleted" => deleted, "commits" => commits, "repository" => { "full_name" => "acme/web", "default_branch" => "main" },
          "installation" => { "id" => 42 } }
      end

      def push_events(files, **) = Github.events(push(files ? [ files ] : [], **), headers: headers_for("push"))

      def repository(action, extra = {})
        Github.events({ "action" => action, "repository" => { "full_name" => "acme/web" } }.merge(extra), headers: headers_for("repository"))
      end
    end
  end
end
