require "test_helper"

module Integrations
  module Packs
    # Cancelling and starting a deploy, and suspending and resuming a service or datastore.
    class RenderControlsTest < ActiveSupport::TestCase
      WEB_PAGE = "https://dashboard.render.com/web/srv-web".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
        @row = @integration.integration_environments.create!
        Render.store_credentials!(@row, Render::API_KEY => "rnd_key")
        @row.store_fields!(Render::WORKSPACE => "tea-1")
        @pack = Render.new(@integration)
        RenderApi.any_instance.stubs(:services).with("tea-1").returns(listed([
          { "id" => "srv-web", "name" => "web", "type" => "web_service", "suspended" => "not_suspended", "dashboardUrl" => WEB_PAGE },
          { "id" => "crn-1", "name" => "nightly", "type" => "cron_job", "suspended" => "suspended", "suspenders" => [ "user" ] }
        ]))
        RenderApi.any_instance.stubs(:postgres_databases).with("tea-1").returns(listed([ { "id" => "dpg-1", "name" => "db", "status" => "suspended" } ]))
        RenderApi.any_instance.stubs(:key_values).with("tea-1").returns(listed([ { "id" => "red-1", "name" => "cache", "status" => "available" } ]))
        RenderApi.any_instance.stubs(:workflows).with("tea-1").returns(listed([ { "id" => "wfl-1", "name" => "mailer" } ]))
      end

      test "a deploy still in progress is cancelled with a link to it, one that ended or a cron job's is refused" do
        RenderApi.any_instance.stubs(:deploy).with("srv-web", "dep-3").returns("id" => "dep-3", "status" => "build_in_progress")
        RenderApi.any_instance.expects(:cancel_deploy).with("srv-web", "dep-3").returns("id" => "dep-3", "status" => "canceled")

        result = @pack.call("cancel_deploy", environment_row: @row, arguments: { "resource" => "web", "deploy" => "dep-3" })
        assert_match "Render is cancelling deploy dep-3 of web, now canceled. The deploy that was live before it keeps serving.", result["content"].sole["text"]
        assert_includes result["content"].sole["text"], "#{WEB_PAGE}/deploys/dep-3"

        RenderApi.any_instance.stubs(:deploy).with("srv-web", "dep-2").returns("id" => "dep-2", "status" => "live")
        assert_match "already ended as live", error(:cancel_deploy, "resource" => "web", "deploy" => "dep-2")
        assert_match "is a cron job", error(:cancel_deploy, "resource" => "nightly", "deploy" => "dep-9")
        RenderApi.any_instance.stubs(:deploy).with("srv-web", "dep-x").raises(RenderApi::NotFound, "Render answered 404")
        assert_match "web has no deploy dep-x", error(:cancel_deploy, "resource" => "web", "deploy" => "dep-x")
      end

      test "whoever triggered a deploy is asked before it is cancelled, and a deploy nobody triggered by hand has nobody to ask" do
        RenderApi.any_instance.stubs(:deploy).with("srv-web", "dep-3").returns("id" => "dep-3", "status" => "update_in_progress", "createdAt" => "2026-10-01T10:00:00Z")
        RenderApi.any_instance.stubs(:events).returns([
          { "timestamp" => "2026-10-01T10:03:00Z", "type" => "deploy_started", "details" => { "deployId" => "dep-3", "trigger" => { "user" => { "id" => "usr-1", "email" => "ana@acme.dev" } } } }
        ])

        owner = @pack.owner_of("cancel_deploy", environment_row: @row, arguments: { "resource" => "web", "deploy" => "dep-3" })
        assert_equal [ "ana@acme.dev", Owner::ROLE_STARTED, "deploy dep-3 of web" ], [ owner.email, owner.role, owner.what ]

        RenderApi.any_instance.stubs(:events).returns([ { "timestamp" => "2026-10-01T10:00:01Z", "type" => "build_started", "details" => { "trigger" => { "newCommit" => "abc" } } } ])
        assert_nil @pack.owner_of("cancel_deploy", environment_row: @row, arguments: { "resource" => "web", "deploy" => "dep-3" })
        assert_nil @pack.owner_of("restart_service", environment_row: @row, arguments: { "resource" => "web" })
      end

      test "a deploy starts with what the spec takes, and fields that cannot go together are refused" do
        RenderApi.any_instance.expects(:trigger_deploy).with("srv-web", { "commitId" => "abc123", "clearCache" => "clear" }).returns("id" => "dep-4", "status" => "created")
        assert_match "Render started deploy dep-4 of web, now created. Autodeploy is as it was.", call(:trigger_deploy, "resource" => "web", "commit" => "abc123", "clear_cache" => true)

        RenderApi.any_instance.expects(:trigger_deploy).with("srv-web", { "deployMode" => "deploy_only" }).returns(nil)
        assert_match "Render queued a deploy of web.", call(:trigger_deploy, "resource" => "web", "deploy_only" => true)

        assert_match "Name a commit or an image, not both", error(:trigger_deploy, "resource" => "web", "commit" => "a", "image" => "ghcr.io/acme/web:1")
        assert_match "takes no commit, image or clear_cache", error(:trigger_deploy, "resource" => "web", "deploy_only" => true, "clear_cache" => true)
        assert_match "leave commit out", error(:trigger_deploy, "resource" => "nightly", "commit" => "abc")
        assert_match "is a Postgres database", error(:trigger_deploy, "resource" => "db")
      end

      test "a service or datastore is suspended and resumed where Render takes it, and one already so is refused" do
        RenderApi.any_instance.expects(:suspend).with(:service, "srv-web").returns(nil)
        assert_match "Render is suspending web. It stops running and serving until resume_service brings it back.", call(:suspend_service, "resource" => "web")
        RenderApi.any_instance.expects(:suspend).with(:key_value, "red-1").returns(nil)
        call(:suspend_service, "resource" => "cache")
        RenderApi.any_instance.expects(:resume).with(:postgres, "dpg-1").returns(nil)
        assert_match "Render is resuming db.", call(:resume_service, "resource" => "db")
        RenderApi.any_instance.expects(:resume).with(:service, "crn-1").returns(nil)
        call(:resume_service, "resource" => "nightly")

        assert_match "nightly is already suspended", error(:suspend_service, "resource" => "nightly")
        assert_match "web is not suspended", error(:resume_service, "resource" => "web")
        assert_match "a workflow, which Render does not suspend", error(:suspend_service, "resource" => "mailer")
      end

      private

      def listed(items) = Pages::Read.new(items: items, complete: true)

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end

      def error(tool, arguments) = assert_raises(NativePack::Error) { call(tool, arguments) }.message
    end
  end
end
