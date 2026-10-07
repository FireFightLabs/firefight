require "test_helper"

module Integrations
  module Packs
    # One Bitbucket connection reading several workspaces, or every one its token can read. A repository names its
    # workspace, so a call about one reaches only that workspace.
    class BitbucketWorkspacesTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Code")
        @row = @integration.integration_environments.create!
        Bitbucket.store_credentials!(@row, Bitbucket::TOKEN => "bb-token")
        @row.store_fields!(Bitbucket::WORKSPACE => %w[acme beta])
        list("/user/workspaces", [ { "workspace" => { "slug" => "acme" } }, { "workspace" => { "slug" => "beta" } } ])
        %w[acme beta].each { |each| list("/repositories/#{each}", [ repository("#{each}/web") ]) }
        BitbucketApi.any_instance.stubs(:get).with { |called, *| called.end_with?("/commits/main") }.returns("values" => [])
      end

      test "several workspaces go on the map, each repository under its own workspace and named with it" do
        webs = Bitbucket.new(@integration).map_of(@row).resources

        assert_equal [ %w[acme acme/web], %w[beta beta/web] ], webs.map { |found| [ found.account, found.external_id ] }
        assert_equal %w[acme beta], webs.map { |found| found.details[ResourceMap::SCOPE] }
      end

      test "every workspace the token can read is listed at each sweep, so one added since is read the next time" do
        @row.store_fields!(Bitbucket::WORKSPACE => [ ALL ])
        list("/user/workspaces", [ { "workspace" => { "slug" => "acme" } }, { "workspace" => { "slug" => "gamma" } } ])
        list("/repositories/gamma", [ repository("gamma/docs") ])

        assert_equal %w[acme/web gamma/docs], Bitbucket.new(@integration).map_of(@row).resources.map(&:external_id)
      end

      test "a token that may not list its workspaces is told which scope that needs" do
        BitbucketApi.any_instance.stubs(:list).with { |called, *| called == "/user/workspaces" }.raises(BitbucketApi::Refused, "Bitbucket answered 403: forbidden")

        error = assert_raises(NativePack::Error) { Bitbucket.scope_options({ Bitbucket::TOKEN => "t" }) }
        assert_match "Listing them needs read:workspace:bitbucket", error.message
        assert_match "read:workspace:bitbucket", Bitbucket.credential_fields.sole.hint
      end

      test "repositories are listed for every workspace the connection reads, each under its workspace" do
        text = Bitbucket.new(@integration).call("list_repositories", environment_row: @row, arguments: {})

        assert_match "Workspace acme:\nacme/web", text
        assert_match "Workspace beta:\nbeta/web", text
      end

      test "a change a delivery names is read in its own workspace, and one in a workspace the connection does not read changes nothing" do
        BitbucketApi.any_instance.stubs(:get).with { |called, *| called == "/repositories/beta/web" }.returns(repository("beta/web"))

        snapshot = Bitbucket.new(@integration).map_refresh(@row, ResourceMap::Scope.new(account: "beta", kind: ResourceMap::KIND_REPOSITORY, external_id: "beta/web"))
        assert_equal [ "beta" ], snapshot.resources.map(&:account)
        assert_empty Bitbucket.new(@integration).map_refresh(@row, ResourceMap::Scope.new(account: "other", kind: ResourceMap::KIND_REPOSITORY, external_id: "other/x")).resources
      end

      test "each workspace gets its own webhook with one secret of Firefight's, and narrowing takes back the dropped one's" do
        %w[acme beta].each { |each| list("/workspaces/#{each}/hooks", []) }
        BitbucketApi.any_instance.expects(:post).with("/workspaces/acme/hooks", has_entries("url" => URL)).returns("uuid" => "{a}")
        BitbucketApi.any_instance.expects(:post).with("/workspaces/beta/hooks", has_entries("url" => URL)).returns("uuid" => "{b}")

        webhook = MapEventSources::Bitbucket.register(@row, url: URL)
        assert_equal [ { "acme" => "{a}", "beta" => "{b}" }, %w[acme beta] ], [ JSON.parse(webhook.id), webhook.scopes ]

        @row.update!(map_events_webhook_id: webhook.id)
        @row.store_fields!(Bitbucket::WORKSPACE => %w[beta])
        list("/workspaces/beta/hooks", [ { "uuid" => "{b}", "url" => URL } ])
        BitbucketApi.any_instance.expects(:delete).with("/workspaces/acme/hooks/%7Ba%7D").returns(nil)
        BitbucketApi.any_instance.expects(:put).with("/workspaces/beta/hooks/%7Bb%7D", anything).returns("uuid" => "{b}")
        assert_equal({ "beta" => "{b}" }, JSON.parse(MapEventSources::Bitbucket.register(@row.reload, url: URL).id))
      end

      private

      def list(path, items) = BitbucketApi.any_instance.stubs(:list).with { |called, *| called == path }.returns([ items, false ])

      def repository(name) = { "full_name" => name, "mainbranch" => { "name" => "main" }, "size" => 10, "links" => { "html" => { "href" => "https://bitbucket.org/#{name}" } } }
    end
  end
end
