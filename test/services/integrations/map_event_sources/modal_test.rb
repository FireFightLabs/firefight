require "test_helper"

module Integrations
  module MapEventSources
    class ModalTest < ActiveSupport::TestCase
      Proto = ModalApi::Proto

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "modal", name: "Modal")
        @row = integration.integration_environments.create!
        Packs::Modal.store_credentials!(@row, Packs::Modal::TOKEN_ID => "ak-1", Packs::Modal::TOKEN_SECRET => "as-1")
        @row.store_fields!(Packs::Modal::ENVIRONMENT => "main")
        stub_apps(app("ap-web", :APP_STATE_DEPLOYED, version: 3), app("ap-scratch", :APP_STATE_EPHEMERAL), app("ap-jobs", :APP_STATE_DEPLOYED, version: 1))
      end

      test "the source polls the app list and has no webhook to verify" do
        assert_equal Modal, MapEvents.source_of("modal")
        assert Modal.polls?
        assert_not Modal.verify(raw_body: "{}", headers: {}, secret: "x")
        assert_match "every 5 minutes", Modal.limits
      end

      test "the first read takes the deployed apps and says nothing, and an app deployed again or rolled back since is read again" do
        first = Modal.poll(@row, since: nil)
        assert_empty first.events
        assert_equal %w[ap-jobs ap-web], JSON.parse(first.cursor)["apps"].keys.sort

        assert_empty Modal.poll(@row, since: first.cursor).events, "nothing changed"
        stub_apps(app("ap-web", :APP_STATE_DEPLOYED, version: 4), app("ap-jobs", :APP_STATE_DEPLOYED, version: 1))
        changed = Modal.poll(@row, since: first.cursor).events.sole

        assert_equal [ ResourceMap::Event::UPDATED, ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: "ap-web") ],
                     [ changed.action, changed.scope ]
      end

      test "an app stopped is followed until it leaves the list, a new deployed app is added, and an ephemeral run is left alone" do
        before = Modal.poll(@row, since: nil).cursor
        stub_apps(app("ap-web", :APP_STATE_STOPPED, version: 3), app("ap-new", :APP_STATE_DEPLOYED, version: 1), app("ap-other-run", :APP_STATE_EPHEMERAL))

        stopped = Modal.poll(@row, since: before)
        assert_equal [ [ ResourceMap::Event::UPDATED, "ap-web" ], [ ResourceMap::Event::ADDED, "ap-new" ], [ ResourceMap::Event::REMOVED, "ap-jobs" ] ],
                     stopped.events.map { |event| [ event.action, event.scope.external_id ] }

        stub_apps(app("ap-new", :APP_STATE_DEPLOYED, version: 1))
        assert_equal [ [ ResourceMap::Event::REMOVED, "ap-web" ] ], Modal.poll(@row, since: stopped.cursor).events.map { |event| [ event.action, event.scope.external_id ] }
      end

      test "a token Modal refuses is said and tried again later, and a slow down stops the read" do
        ModalApi.any_instance.stubs(:apps).raises(ModalApi::Refused, "Modal answered permission denied: no access")
        assert_raises(MapEventSource::Refused) { Modal.poll(@row, since: nil) }

        ModalApi.any_instance.stubs(:apps).raises(ModalApi::RateLimited, "Modal answered resource exhausted: slow down")
        assert_raises(ModalApi::RateLimited) { Modal.poll(@row, since: nil) }
      end

      private

      def app(id, state, version: 0)
        Proto::AppListResponse::AppListItem.new(app_id: id, description: id.delete_prefix("ap-"), state: state,
                                                metadata: Proto::AppHandleMetadata.new(lifecycle: Proto::AppLifecycle.new(version: version)))
      end

      def stub_apps(*apps)
        ModalApi.any_instance.stubs(:apps).with("main").returns(apps)
      end
    end
  end
end
