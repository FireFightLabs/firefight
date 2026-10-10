require "test_helper"

module Integrations
  module Packs
    class ConvexTest < ActiveSupport::TestCase
      INFO = { "kind" => "cloud", "teamId" => 7, "projectId" => 42, "projectName" => "Chat", "projectSlug" => "chat",
               "id" => 99, "deploymentType" => "prod" }.freeze
      URL = "https://happy-animal-123.convex.cloud".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Convex::PROVIDER_KEY, name: "Convex")
        @row = @integration.integration_environments.create!
        Convex.store_credentials!(@row, Convex::DEPLOY_KEY => " prod:happy-animal-123|key ")
        @row.store_fields!(Convex::DEPLOYMENT_URL => "#{URL}/")
        @pack = Convex.new(@integration)
        ConvexApi.any_instance.stubs(:deployment_info).returns(INFO)
        ConvexApi.any_instance.stubs(:environment_variables).returns({})
        travel_to Time.zone.parse("2026-10-04T12:00:00Z")
      end

      test "the key is stored trimmed, the URL is a field of the form, every tool only reads, and the form refuses a URL Convex does not host" do
        assert_nil @row.reload.credentials_hash[Convex::DEPLOYMENT_URL]
        assert_equal "prod:happy-animal-123|key", @row.credentials_hash[Convex::DEPLOY_KEY]
        assert_equal [ Convex::DEPLOY_KEY ], Convex.credential_fields.map(&:key)
        assert Convex.tool_definitions.all?(&:read_only)
        assert_match "ends in convex.cloud", Convex.credential_refusal({ Convex::DEPLOY_KEY => "x" }, fields: { Convex::DEPLOYMENT_URL => "http://10.0.0.1" })
        assert_nil Convex.credential_refusal({ Convex::DEPLOY_KEY => "x" }, fields: { Convex::DEPLOYMENT_URL => URL })
        ConvexApi.any_instance.stubs(:deployment_info).raises(ConvexApi::Error, "Convex answered 401: bad key")
        assert_equal "Convex refused this deployment URL or deploy key: Convex answered 401: bad key.",
                     Convex.credential_refusal({ Convex::DEPLOY_KEY => "x" }, fields: { Convex::DEPLOYMENT_URL => URL })
      end

      test "logs read from the start of the range, newest first, filtered, with each failure's error and a link to the deployment" do
        ConvexApi.any_instance.expects(:function_logs).with(cursor: (Time.current - 30.minutes).to_i * 1000).returns("entries" => [
          execution("messages:send", 20.minutes.ago, lines: [ { "level" => "INFO", "messages" => [ "sending", "hello" ], "timestamp" => (19.minutes.ago.to_f * 1000).to_i, "isTruncated" => false } ]),
          execution("messages:list", 10.minutes.ago, lines: [ "plain line" ], error: "Uncaught Error: boom at handler"),
          execution("users:get", 5.minutes.ago, lines: [ "noise" ])
        ], "newCursor" => 1)

        text = call(:search_logs, "minutes" => 30, "exclude" => "noise")
        lines = text.lines.map(&:strip)

        assert_match "3 log lines for happy-animal-123", lines.first
        assert_match "Query messages:list ERROR failed: Uncaught Error: boom", lines[1]
        assert_match "Query messages:list plain line", lines[2]
        assert_match "Query messages:send INFO sending hello", lines[3]
        assert_match %r{link with what you found: https://dashboard\.convex\.dev/d/happy-animal-123\z}, text
        assert_match "oldest execution it still keeps", text
      end

      test "failures only, and a function, narrow the executions read" do
        ConvexApi.any_instance.stubs(:function_logs).returns("entries" => [
          execution("messages:send", 59.minutes.ago, lines: [ "ok" ]),
          execution("messages:list", 10.minutes.ago, lines: [ "about to fail" ], error: "Uncaught Error: boom"),
          execution("users:get", 5.minutes.ago, lines: [ "other" ], error: "Uncaught Error: other")
        ], "newCursor" => 1)

        text = call(:search_logs, "failures_only" => true, "function" => "messages")

        assert_match "about to fail", text
        assert_no_match "users:get", text
        assert_no_match(/messages:send/, text)
        assert_no_match "oldest execution", text
      end

      test "errors are grouped by function and error, most frequent first, with retries named" do
        ConvexApi.any_instance.stubs(:function_logs).returns("entries" => [
          execution("counters:add", 50.minutes.ago, error: "Documents read from or written to the table \"counters\" changed while this mutation was being run", type: "Mutation", retried: true),
          execution("counters:add", 40.minutes.ago, error: "Documents read from or written to the table \"counters\" changed while this mutation was being run", type: "Mutation"),
          execution("files:upload", 30.minutes.ago, error: "Uncaught Error: token ghp_#{'a' * 36}"),
          execution("files:list", 20.minutes.ago)
        ], "newCursor" => 1)

        text = call(:function_errors, {})

        assert_match "3 failed executions of 4 read on happy-animal-123", text
        rows = text.lines.map(&:strip)
        assert rows[1].start_with?("2 times, Mutation counters:add, last 2026-10-04T11:20:00Z, 1 will be retried")
        redacted = Integrations::Redactions.apply(@pack.call("function_errors", environment_row: @row, arguments: {}))["content"].first["text"]
        assert_match "[REDACTED:github_token]", redacted
        assert_match "No function of happy-animal-123 failed", call(:function_errors, "text" => "nothing like this")
      end

      test "pushes come newest first from the audit log, with who made them, across pages" do
        first = { "items" => [ event("push_config", 3.days.ago, "kind" => "member", "member_id" => 5), event("update_environment_variable", 2.days.ago) ],
                  "pagination" => { "hasMore" => true, "nextCursor" => "next" } }
        second = { "items" => [ event("push_config_with_components", 1.day.ago, "kind" => "token", "token_id" => 9) ], "pagination" => { "hasMore" => false } }
        ConvexApi.any_instance.expects(:audit_log).with(from: (30.days.ago.to_f * 1000).to_i, cursor: nil).returns(first)
        ConvexApi.any_instance.expects(:audit_log).with(from: (30.days.ago.to_f * 1000).to_i, cursor: "next").returns(second)

        rows = call(:recent_pushes, {}).lines.map(&:strip)

        assert_match "Latest 2 pushes to happy-animal-123, newest first", rows[0]
        assert rows[1].start_with?("2026-10-03T12:00:00Z, push_config_with_components, by a deploy key or token (token 9)")
        assert rows[2].start_with?("2026-10-01T12:00:00Z, push_config, by a member in the dashboard (member 5)")
        assert_no_match "environment_variable", rows.join
      end

      test "status says who the deployment is, its URLs, and a pause in the last week" do
        ConvexApi.any_instance.stubs(:canonical_urls).returns("convexCloudUrl" => URL, "convexSiteUrl" => "https://happy-animal-123.convex.site")
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [ event("pause_deployment", 2.hours.ago, "kind" => "member", "member_id" => 5) ],
                                                         "pagination" => { "hasMore" => false })

        text = call(:deployment_status, {})

        assert_match "happy-animal-123, the prod deployment of project Chat", text
        assert_match "https://happy-animal-123.convex.site (HTTP actions)", text
        assert_match "pause_deployment, by a member in the dashboard", text
      end

      test "status never says the deployment runs as usual from an audit log cut short" do
        ConvexApi.any_instance.stubs(:canonical_urls).returns("convexCloudUrl" => URL)
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [ event("push_config", 6.days.ago) ], "pagination" => { "hasMore" => true, "nextCursor" => "more" })

        text = call(:deployment_status, {})

        assert_no_match "running as usual", text
        assert_match "only the oldest were read, so whether it was paused since is not known", text

        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [ event("pause_deployment", 6.days.ago) ], "pagination" => { "hasMore" => true, "nextCursor" => "more" })
        text = call(:deployment_status, {})

        assert_match "pause_deployment", text
        assert_match "only the oldest were read, so whether it was paused since is not known", text
      end

      test "the deployment's environment variables are read in memory for where they point, and a key that may not read them is a gap" do
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [], "pagination" => { "hasMore" => false })
        ConvexApi.any_instance.stubs(:environment_variables).returns("DATABASE_URL" => "postgres://app:convex-pass@ep-a.neon.tech/app", "LOG_LEVEL" => "debug")

        snapshot = @pack.map_of(@row)

        assert_equal [ "DATABASE_URL" ], snapshot.uses.map(&:variable)
        assert_equal ResourceMap::Fingerprint.of("ep-a.neon.tech", 5432, @workspace), snapshot.uses.sole.fingerprint
        assert_no_setting_values(snapshot, "convex-pass", "ep-a.neon.tech", "postgres://app:convex-pass@ep-a.neon.tech/app")

        ConvexApi.any_instance.stubs(:environment_variables).raises(ConvexApi::Error, "Convex answered 403: forbidden")
        refused = @pack.map_of(@row)
        assert refused.complete?
        assert_not refused.settings_complete?
        assert_match(/may read environment variables/, refused.gaps.sole.text)
      end

      test "the map holds the deployment under its project, with its dashboard page and its state, and the health check reads it" do
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [], "pagination" => { "hasMore" => false })
        snapshot = @pack.map_of(@row)
        found = snapshot.resources.sole

        assert_equal [ Convex::PROVIDER_KEY, "chat", ResourceMap::KIND_SERVICE, "happy-animal-123" ], found.key
        assert_equal "https://dashboard.convex.dev/d/happy-animal-123", found.url
        assert_equal({ "project" => "Chat", "type" => "prod" }, found.details)
        assert_equal "running", found.status
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [ event("pause_deployment", 2.hours.ago) ], "pagination" => { "hasMore" => false })
        assert_equal "paused", @pack.map_of(@row).resources.sole.status
        ConvexApi.any_instance.stubs(:audit_log).returns("items" => [ event("unpause_deployment", 6.days.ago) ], "pagination" => { "hasMore" => true, "nextCursor" => "more" })
        assert_nil @pack.map_of(@row).resources.sole.status, "an audit log cut short may hide a later pause, so its state is not known"
        assert_nil @pack.check_health!(@row).then { nil }
        ConvexApi.any_instance.stubs(:deployment_info).raises(ConvexApi::Error, "Convex answered 401: bad key")
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def call(tool, arguments)
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].first["text"]
      end

      def execution(identifier, at, lines: [], error: nil, type: "Query", retried: false)
        { "kind" => "Completion", "udfType" => type, "identifier" => identifier, "timestamp" => at.to_f, "logLines" => lines,
          "error" => error, "willRetry" => retried, "executionId" => SecureRandom.hex(4) }
      end

      def event(action, at, actor = { "kind" => "system" })
        { "action" => action, "createTime" => (at.to_f * 1000).to_i, "actor" => actor, "metadata" => {} }
      end
    end
  end
end
