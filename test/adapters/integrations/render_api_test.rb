require "test_helper"

module Integrations
  class RenderApiTest < ActiveSupport::TestCase
    setup do
      @api = RenderApi.new("rnd_key")
    end

    test "a list filter is sent once per value with the key, and a log page comes back as Render answered it" do
      Http.expects(:request).with do |uri, request, **|
        query = URI.decode_www_form(uri.query)
        uri.path == "/v1/logs" && request["Authorization"] == "Bearer rnd_key" && request["Accept"] == "application/json" &&
          query.count { |name, _| name == "text" } == 2 && query.include?([ "ownerId", "tea-1" ]) && query.none? { |name, _| name.include?("[") }
      end.returns(response(200, { hasMore: false, logs: [] }))

      assert_equal({ "hasMore" => false, "logs" => [] }, @api.logs("ownerId" => "tea-1", "resource" => "srv-1", "text" => [ "timeout", "/5../" ]))
    end

    test "a list is read page by page from the last cursor, and only the rows come back" do
      first = Array.new(RenderApi::PAGE_SIZE) { |index| { cursor: "c#{index}", service: { id: "srv-#{index}" } } }
      Http.expects(:request).with { |uri, *| !uri.query.include?("cursor") }.returns(response(200, first))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).include?([ "cursor", "c#{RenderApi::PAGE_SIZE - 1}" ]) }
          .returns(response(200, [ { cursor: "last", service: { id: "srv-last" } } ]))

      services = @api.services("tea-1")

      assert_equal RenderApi::PAGE_SIZE + 1, services.items.size
      assert_equal "srv-last", services.items.last["id"]
      assert_not services.incomplete?
    end

    test "a list still going at the last page it reads says it was not read to its end" do
      full = Array.new(RenderApi::PAGE_SIZE) { |index| { cursor: "c#{index}", postgres: { id: "dpg-#{index}" } } }
      Http.stubs(:request).returns(response(200, full))

      databases = @api.postgres_databases("tea-1")

      assert databases.incomplete?
      assert_equal RenderApi::PAGE_SIZE * RenderApi::MAX_PAGES, databases.items.size
    end

    test "a change is sent as JSON, and Render's refusal comes back in its own words" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/services/srv-1/scale" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "numInstances" => 3 }
      end.returns(stub(code: "202", body: ""))
      assert_equal({}, @api.scale("srv-1", 3))

      Http.stubs(:request).returns(response(403, { id: "x", message: "You do not have permissions for the requested resource." }))
      error = assert_raises(RenderApi::Error) { @api.restart_service("srv-1") }
      assert_equal "Render answered 403: You do not have permissions for the requested resource.", error.message
    end

    test "a webhook is made for the workspace with the events named, switched on again, and deleted, at the paths the spec gives" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/webhooks" && request.is_a?(Net::HTTP::Post) &&
          JSON.parse(request.body) == { "ownerId" => "tea-1", "name" => "Firefight", "url" => "https://ff.example/hook", "enabled" => true, "eventFilter" => [ "deploy_ended" ] }
      end.returns(response(201, { id: "whk-1", secret: "whsec_abc" }))
      assert_equal "whsec_abc", @api.create_webhook("tea-1", name: "Firefight", url: "https://ff.example/hook", events: [ "deploy_ended" ])["secret"]

      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/webhooks/whk-1" && request.is_a?(Net::HTTP::Patch) && JSON.parse(request.body) == { "enabled" => true, "eventFilter" => [ "deploy_ended" ] }
      end.returns(response(200, { id: "whk-1", enabled: true }))
      assert @api.update_webhook("whk-1", events: [ "deploy_ended" ])["enabled"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/webhooks/whk-1" && request.is_a?(Net::HTTP::Delete) }.returns(stub(code: "204", body: ""))
      assert_equal({}, @api.delete_webhook("whk-1"))

      Http.expects(:request).with { |uri, *| uri.path == "/v1/webhooks" && URI.decode_www_form(uri.query).include?([ "ownerId", "tea-1" ]) }
          .returns(response(200, [ { cursor: "c1", webhook: { id: "whk-1", url: "https://ff.example/hook" } } ]))
      assert_equal [ "whk-1" ], @api.webhooks("tea-1").items.map { |webhook| webhook["id"] }
    end

    test "runs, instances, deploy changes and suspending reach the paths the spec gives" do
      expect_call(Net::HTTP::Get, "/v1/services/srv-1/instances", [ { id: "srv-1-abcde", createdAt: "2026-10-01T10:00:00Z" } ])
      assert_equal [ "srv-1-abcde" ], @api.instances("srv-1").map { |instance| instance["id"] }
      expect_call(Net::HTTP::Get, "/v1/services/srv-1/jobs", [ { cursor: "c", job: { id: "job-1" } } ], query: [ "limit", "5" ])
      assert_equal [ "job-1" ], @api.jobs("srv-1", limit: 5).map { |job| job["id"] }
      expect_call(Net::HTTP::Get, "/v1/services/srv-1/jobs/job-1", { id: "job-1" })
      assert_equal "job-1", @api.job("srv-1", "job-1")["id"]
      expect_call(Net::HTTP::Get, "/v1/task-runs", [ { cursor: "c", taskRun: { id: "trn-1" } } ], query: [ "workflowId", "wfl-1" ])
      assert_equal [ "trn-1" ], @api.task_runs("wfl-1", limit: 20).map { |run| run["id"] }
      expect_call(Net::HTTP::Get, "/v1/task-runs", [], query: [ "rootTaskRunId", "trn-1" ])
      assert_empty @api.child_task_runs("trn-1")
      expect_call(Net::HTTP::Get, "/v1/task-runs/trn-1", { id: "trn-1" })
      assert_equal "trn-1", @api.task_run("trn-1")["id"]
      expect_call(Net::HTTP::Get, "/v1/tasks", [ { cursor: "c", task: { id: "tsk-1", name: "send" } } ], query: [ "workflowId", "wfl-1" ])
      assert_equal [ "send" ], @api.tasks("wfl-1").items.map { |task| task["name"] }
      expect_call(Net::HTTP::Get, "/v1/workflows", [ { cursor: "c", workflow: { id: "wfl-1" } } ], query: [ "ownerId", "tea-1" ])
      assert_equal [ "wfl-1" ], @api.workflows("tea-1").items.map { |workflow| workflow["id"] }

      expect_call(Net::HTTP::Patch, "/v1/services/srv-1", { id: "srv-1" }, body: { "autoDeployTrigger" => "off" })
      @api.update_autodeploy("srv-1", "off")
      config = { "enabled" => true, "min" => 1, "max" => 3, "criteria" => { "cpu" => { "enabled" => true, "percentage" => 60 }, "memory" => { "enabled" => false, "percentage" => 70 } } }
      expect_call(Net::HTTP::Put, "/v1/services/srv-1/autoscaling", config, body: config)
      @api.update_autoscaling("srv-1", config)
      expect_call(Net::HTTP::Post, "/v1/cron-jobs/crn-1/runs", { id: "run-1", status: "pending" })
      assert_equal "run-1", @api.trigger_cron_run("crn-1")["id"]
      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/cron-jobs/crn-1/runs" && request.is_a?(Net::HTTP::Delete) }.returns(stub(code: "204", body: ""))
      @api.cancel_cron_run("crn-1")
      expect_call(Net::HTTP::Post, "/v1/services/srv-1/jobs", { id: "job-2" }, body: { "startCommand" => "ls", "planId" => "plan-srv-006" })
      assert_equal "job-2", @api.create_job("srv-1", "ls", plan_id: "plan-srv-006")["id"]
      expect_call(Net::HTTP::Post, "/v1/services/srv-1/jobs/job-1/cancel", { id: "job-1", status: "canceled" })
      assert_equal "canceled", @api.cancel_job("srv-1", "job-1")["status"]
      expect_call(Net::HTTP::Post, "/v1/task-runs", { id: "trn-2" }, body: { "task" => "mailer/send", "input" => [ 1 ] })
      assert_equal "trn-2", @api.run_task("mailer/send", [ 1 ])["id"]
      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/task-runs/trn-2" && request.is_a?(Net::HTTP::Delete) }.returns(stub(code: "204", body: ""))
      @api.cancel_task_run("trn-2")
      expect_call(Net::HTTP::Post, "/v1/services/srv-1/deploys/dep-1/cancel", { id: "dep-1", status: "canceled" })
      assert_equal "canceled", @api.cancel_deploy("srv-1", "dep-1")["status"]
      expect_call(Net::HTTP::Post, "/v1/services/srv-1/deploys", { id: "dep-2" }, body: { "clearCache" => "clear" })
      assert_equal "dep-2", @api.trigger_deploy("srv-1", "clearCache" => "clear")["id"]
      [ [ :service, "/v1/services/srv-1" ], [ :postgres, "/v1/postgres/dpg-1" ], [ :key_value, "/v1/key-value/red-1" ] ].each do |kind, path|
        id = path.split("/").last
        Http.expects(:request).with { |uri, request, **| uri.path == "#{path}/suspend" && request.is_a?(Net::HTTP::Post) }.returns(stub(code: "202", body: ""))
        @api.suspend(kind, id)
        Http.expects(:request).with { |uri, request, **| uri.path == "#{path}/resume" && request.is_a?(Net::HTTP::Post) }.returns(stub(code: "202", body: ""))
        @api.resume(kind, id)
      end
    end

    test "not found and a request turned down as it stands are told apart from other refusals" do
      Http.stubs(:request).returns(response(404, { message: "not found" }))
      assert_raises(RenderApi::NotFound) { @api.service("srv-1") }

      Http.stubs(:request).returns(response(400, { message: "webhooks are not available on your plan" }))
      assert_raises(RenderApi::Refused) { @api.create_webhook("tea-1", name: "Firefight", url: "https://ff.example/hook", events: []) }

      Http.stubs(:request).returns(response(401, { message: "unauthorized" }))
      error = assert_raises(RenderApi::Error) { @api.owner("tea-1") }
      assert_not error.is_a?(RenderApi::Refused)
    end

    test "being asked to slow down is its own error" do
      Http.stubs(:request).returns(response(429, { message: "rate limit exceeded" }))

      assert_raises(Integrations::RateLimited) { @api.owner("tea-1") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end

    def expect_call(method, path, answer, query: nil, body: nil)
      Http.expects(:request).with do |uri, request, **|
        uri.path == path && request.is_a?(method) && (query.nil? || URI.decode_www_form(uri.query.to_s).include?(query)) &&
          (body.nil? || JSON.parse(request.body) == body)
      end.returns(response(200, answer))
    end
  end
end
