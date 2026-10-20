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

      test "autodeploy is set by its trigger, the one before is named for the undo, and its undo sets it back on its own" do
        RenderApi.any_instance.stubs(:service).with("srv-web").returns("id" => "srv-web", "autoDeployTrigger" => "commit")
        RenderApi.any_instance.expects(:update_autodeploy).with("srv-web", "off").returns({})

        result = @pack.call("set_autodeploy", environment_row: @row, arguments: { "resource" => "web", "trigger" => "off" })
        assert_match "Autodeploy of web is now off. It was on each commit.", result["content"].sole["text"]
        assert_equal({ "before" => "commit" }, result.dig(Telemetry::STRUCTURED, Telemetry::FACTS))

        @integration.update!(slug: "render")
        Render.tool_definitions.each do |definition|
          @integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                     params_schema: definition.params_schema)
        end
        tool = @integration.tools.find_by!(name: "set_autodeploy")
        assert SafeChanges.tool?(tool)
        undo = SafeChanges.inverse(tool, { "resource" => "web", "trigger" => "off" }, result)
        assert_equal [ "set_autodeploy", { "resource" => "web", "trigger" => "commit" } ], [ undo.tool.name, undo.arguments ]

        assert_match "already on each commit", error(:set_autodeploy, "resource" => "web", "trigger" => "commit")
        assert_match "trigger must be commit, checksPass or off", error(:set_autodeploy, "resource" => "web", "trigger" => "never")
        assert_match "is a Postgres database", error(:set_autodeploy, "resource" => "db", "trigger" => "off")
      end

      test "autoscaling keeps what is not given, sends every field Render requires, and refuses a range or target that cannot work" do
        RenderApi.any_instance.stubs(:service).with("srv-web").returns("serviceDetails" => {
          "autoscaling" => { "enabled" => true, "min" => 2, "max" => 4, "criteria" => { "cpu" => { "enabled" => true, "percentage" => 70 }, "memory" => { "enabled" => false, "percentage" => 80 } } }
        })
        RenderApi.any_instance.expects(:update_autoscaling).with("srv-web", {
          "enabled" => true, "min" => 2, "max" => 8,
          "criteria" => { "cpu" => { "enabled" => true, "percentage" => 70 }, "memory" => { "enabled" => true, "percentage" => 75 } }
        }).returns({})
        assert_match "Autoscaling of web is now on, between 2 and 8 instances, aiming for cpu 70% and memory 75%. It was on, between 2 and 4 instances, aiming for cpu 70%.",
                     call(:set_autoscaling, "resource" => "web", "max" => 8, "memory_percent" => 75)

        RenderApi.any_instance.expects(:update_autoscaling).with("srv-web", has_entries("enabled" => false, "min" => 2, "max" => 4)).returns({})
        assert_match "now off", call(:set_autoscaling, "resource" => "web", "enabled" => false)

        assert_match "max at least min", error(:set_autoscaling, "resource" => "web", "min" => 5, "max" => 3)
        assert_match "cpu_percent must be from 1 to 100", error(:set_autoscaling, "resource" => "web", "cpu_percent" => 150)
        assert_match "needs a CPU or memory target", error(:set_autoscaling, "resource" => "web", "cpu_percent" => 0)
        assert_match "Render autoscales web services", error(:set_autoscaling, "resource" => "nightly", "max" => 3)

        RenderApi.any_instance.stubs(:service).with("srv-web").returns("serviceDetails" => {})
        assert_match "Say the fewest and the most instances", error(:set_autoscaling, "resource" => "web", "enabled" => true, "cpu_percent" => 60)
        RenderApi.any_instance.expects(:update_autoscaling).with("srv-web", {
          "enabled" => true, "min" => 1, "max" => 3,
          "criteria" => { "cpu" => { "enabled" => true, "percentage" => 60 }, "memory" => { "enabled" => false, "percentage" => Render::Controls::UNUSED_PERCENT } }
        }).returns({})
        assert_match "It was never set up.", call(:set_autoscaling, "resource" => "web", "enabled" => true, "min" => 1, "max" => 3, "cpu_percent" => 60)
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
