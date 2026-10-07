require "test_helper"

module Integrations
  module MapEventSources
    class BitbucketTest < ActiveSupport::TestCase
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      HOOKS = "/workspaces/acme/hooks".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
        @row = @integration.integration_environments.create!
        @row.store_fields!(Packs::Bitbucket::WORKSPACE => "acme")
        Packs::Bitbucket.store_credentials!(@row, Packs::Bitbucket::TOKEN => "bb-token")
        BitbucketApi.any_instance.expects(:delete).never
      end

      test "a delivery signed with the webhook's secret is Bitbucket's, matching Bitbucket's own example, and one signed otherwise is not" do
        # The example in Bitbucket's docs (support.atlassian.com, Manage webhooks, Secure webhooks).
        example = { "x-hub-signature" => "sha256=a4771c39fbe90f317c7824e83ddef3caae9cb3d976c214ace1f2937e133263c9" }
        assert Bitbucket.verify(raw_body: "Hello World!", headers: example, secret: "It's a Secret to Everybody")

        assert_not Bitbucket.verify(raw_body: "Hello World?", headers: example, secret: "It's a Secret to Everybody")
        assert_not Bitbucket.verify(raw_body: "Hello World!", headers: example, secret: "another secret")
        assert_not Bitbucket.verify(raw_body: "Hello World!", headers: { "x-hub-signature" => example["x-hub-signature"].sub("sha256=", "sha1=") },
                                    secret: "It's a Secret to Everybody")
        assert_not Bitbucket.verify(raw_body: "Hello World!", headers: {}, secret: "It's a Secret to Everybody")
        assert_not Bitbucket.verify(raw_body: "Hello World!", headers: example, secret: nil)
      end

      test "a push names each branch it moved, for the pack to read the repository when it is the main one" do
        events = Bitbucket.events(push({ "type" => "branch", "name" => "main" }, { "type" => "branch", "name" => "feature/x" }, { "type" => "tag", "name" => "v1" }, nil),
                                  headers: headers_for(Bitbucket::PUSH))

        assert_equal [ [ "request-1:main", "acme/web/main" ], [ "request-1:feature/x", "acme/web/feature/x" ] ], events.map { |event| [ event.id, event.scope.external_id ] }
        assert events.all? { |event| event.scope.kind == ResourceMap::KIND_BRANCH && event.scope.account == "acme" && event.action == ResourceMap::Event::UPDATED }
      end

      test "a repository created, imported or deleted is read again, and one renamed or transferred rescopes the workspace" do
        assert_equal [ ResourceMap::Event::ADDED ], repository_event(Bitbucket::CREATED).map(&:action)
        assert_equal [ ResourceMap::Event::ADDED ], repository_event(Bitbucket::IMPORTED).map(&:action)
        deleted = repository_event(Bitbucket::DELETED).sole
        assert_equal [ ResourceMap::Event::REMOVED, ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web") ], [ deleted.action, deleted.scope ]

        assert repository_event(Bitbucket::TRANSFER).sole.rescope?
        assert repository_event(Bitbucket::UPDATED, "changes" => { "full_name" => { "new" => "acme/web", "old" => "acme/site" } }).sole.rescope?
        assert_empty repository_event(Bitbucket::UPDATED, "changes" => { "description" => { "new" => "a", "old" => "b" } })
        assert_empty repository_event("pullrequest:created")
      end

      test "registering adds a workspace webhook for the events the map reads, beside one at another address that it leaves alone" do
        BitbucketApi.any_instance.stubs(:list).with(HOOKS).returns([ [ { "uuid" => "{theirs}", "url" => "https://example.com/hook" } ], false ])
        BitbucketApi.any_instance.expects(:put).never
        BitbucketApi.any_instance.expects(:post).with(HOOKS, has_entries("url" => URL, "active" => true, "events" => Bitbucket::EVENTS)).returns("uuid" => "{ours}")

        webhook = Bitbucket.register(@row, url: URL)

        assert_equal({ "acme" => "{ours}" }, JSON.parse(webhook.id))
        assert_equal [ "acme" ], webhook.scopes
        assert_match(/\A\h{64}\z/, webhook.secret)
      end

      test "Firefight's webhook from before at this address gets a new secret, since Bitbucket never shows one again" do
        BitbucketApi.any_instance.stubs(:list).with(HOOKS).returns([ [ { "uuid" => "{theirs}", "url" => "https://example.com/hook" }, { "uuid" => "{ours}", "url" => URL } ], false ])
        BitbucketApi.any_instance.expects(:post).never
        BitbucketApi.any_instance.expects(:put).with("#{HOOKS}/%7Bours%7D", has_key("secret")).returns("uuid" => "{ours}")

        assert_equal({ "acme" => "{ours}" }, JSON.parse(Bitbucket.register(@row, url: URL).id))
      end

      test "a token that is not a workspace owner's, or lacks the webhook scopes, is told why" do
        BitbucketApi.any_instance.stubs(:list).with(HOOKS).raises(BitbucketApi::Refused, "Bitbucket answered 403: Your credentials lack one or more required privilege scopes.")

        refusal = assert_raises(MapEventSource::Refused) { Bitbucket.register(@row, url: URL) }

        assert_equal "Bitbucket answered 403: Your credentials lack one or more required privilege scopes. #{Bitbucket::OWNER_NOTE}.", refusal.message
      end

      test "removing takes back Firefight's webhook, and one Bitbucket no longer has is done" do
        BitbucketApi.any_instance.unstub(:delete)
        BitbucketApi.any_instance.expects(:delete).with("#{HOOKS}/%7Bours%7D").returns(nil)
        Bitbucket.remove(@row, "{ours}")

        BitbucketApi.any_instance.stubs(:delete).raises(BitbucketApi::NotFound, "Bitbucket answered 404: not found")
        assert_nothing_raised { Bitbucket.remove(@row, { "acme" => "{gone}" }.to_json) }
      end

      private

      def headers_for(event) = { "x-event-key" => event, "x-request-uuid" => "request-1" }

      def push(*news)
        { "repository" => { "full_name" => "acme/web" }, "push" => { "changes" => news.map { |new| { "new" => new, "old" => nil } } } }
      end

      def repository_event(event, extra = {})
        Bitbucket.events({ "repository" => { "full_name" => "acme/web" } }.merge(extra), headers: headers_for(event))
      end
    end
  end
end
