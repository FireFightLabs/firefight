require "test_helper"

module Integrations
  module Packs
    class ModalTest < ActiveSupport::TestCase
      Proto = ModalApi::Proto
      APP_ID = "ap-#{'a' * 22}".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "modal", name: "Modal")
        @row = @integration.integration_environments.create!
        Modal.store_credentials!(@row, Modal::TOKEN_ID => " ak-1 ", Modal::TOKEN_SECRET => " as-1 ")
        @row.store_fields!(Modal::ENVIRONMENT => "main")
        @pack = Modal.new(@integration)
        lifecycle = Proto::AppLifecycle.new(app_state: :APP_STATE_DEPLOYED, version: 7, deployed_at: Time.utc(2026, 10, 3, 9).to_f, deployed_by: "ana",
                                            created_at: Time.utc(2026, 9, 1).to_f)
        ModalApi.any_instance.stubs(:deployed).with("inference", "main").returns(Proto::AppGetByDeploymentNameResponse.new(app_id: APP_ID, lifecycle: lifecycle))
        ModalApi.any_instance.stubs(:lifecycle).with(APP_ID).returns(lifecycle)
        summary = Proto::AppGetInfoResponse::FunctionInfoSummary.new(gpu_config: [ Proto::GPUConfig.new(count: 1, gpu_type: "H100") ],
                                                                     schedule: Proto::Schedule.new(cron: Proto::Schedule::Cron.new(cron_string: "0 * * * *")))
        ModalApi.any_instance.stubs(:info).with(APP_ID).returns(Proto::AppGetInfoResponse.new(
          info: Proto::AppHandleMetadata.new(description: "inference", app_id: APP_ID, lifecycle: lifecycle, functions: { "generate" => "fu-1" }, servers: { "web" => "fu-2" }),
          function_info_summaries: { "fu-1" => summary, "fu-2" => Proto::AppGetInfoResponse::FunctionInfoSummary.new(web_function: true, requires_proxy_auth: false) }
        ))
      end

      test "the token is stored trimmed, the environment is a field of the form, and only the five changes are not read only" do
        assert_equal [ "ak-1", "as-1", nil ], @row.reload.credentials_hash.values_at(Modal::TOKEN_ID, Modal::TOKEN_SECRET, Modal::ENVIRONMENT)
        assert_equal "main", ConnectionSettings.of(@row).field(Modal::ENVIRONMENT)
        assert_equal [ Modal::TOKEN_ID, Modal::TOKEN_SECRET ], Modal.credential_fields.map(&:key)
        assert_equal %w[rollback_app rollover_app stop_container stop_app update_autoscaler], Modal.tool_definitions.reject(&:read_only).map(&:name)
        assert_equal %w[stop_container stop_app], IntegrationProvider.find("modal").stopping_tools
        assert Modal.credential_fields.find { |field| field.key == Modal::TOKEN_SECRET }.secret
      end

      test "a wrong token or environment is said on the form before anything is saved" do
        ModalApi.any_instance.stubs(:workspace).returns("acme")
        ModalApi.any_instance.stubs(:apps).with("staging").raises(ModalApi::NotFound, "Modal answered not found: no environment")
        assert_match "no environment called staging", Modal.credential_refusal({ Modal::TOKEN_ID => "ak", Modal::TOKEN_SECRET => "as" }, fields: { Modal::ENVIRONMENT => "staging" })
        assert_equal "Paste the token secret.", Modal.credential_refusal({ Modal::TOKEN_ID => "ak" })
        ModalApi.any_instance.stubs(:apps).with("").returns([])
        assert_nil Modal.credential_refusal({ Modal::TOKEN_ID => "ak", Modal::TOKEN_SECRET => "as" })
      end

      test "apps list those running most containers first, each with its state and page" do
        ModalApi.any_instance.stubs(:apps).with("main").returns([
          Proto::AppListResponse::AppListItem.new(app_id: "ap-old", description: "scratch", state: :APP_STATE_STOPPED, created_at: 1.0, stopped_at: 2.0),
          Proto::AppListResponse::AppListItem.new(app_id: APP_ID, description: "inference", state: :APP_STATE_DEPLOYED, n_running_tasks: 3, created_at: 1.0)
        ])

        lines = call(:list_apps).lines

        assert_equal "2 apps in main, those running most containers first, each with its page in Modal.\n", lines.first
        assert_match "inference (#{APP_ID}), deployed, 3 containers running, created 1970-01-01T00:00:01Z, page https://modal.com/id/#{APP_ID}", lines.second
        assert_match "scratch (ap-old), stopped, 0 containers running, created 1970-01-01T00:00:01Z, stopped 1970-01-01T00:00:02Z", lines.third
      end

      test "an app reads as modal app info does, with its functions, and links to the page modal app dashboard opens" do
        ModalApi.any_instance.stubs(:containers).with(APP_ID, "main").returns([ Proto::TaskStats.new(task_id: "ta-1") ])

        text = call(:describe_app, "app" => "inference")

        assert_match "inference (#{APP_ID}), deployed", text
        assert_match "Deployed version v7 at 2026-10-03T09:00:00Z by ana", text
        assert_match "Containers running now: 1", text
        assert_match "generate (fu-1), 1 x H100 GPU, runs on cron 0 * * * * (UTC)", text
        assert_match "web (fu-2), CPU, web, open to anyone, no proxy auth", text
        assert_match "https://modal.com/id/#{APP_ID}", text
        assert_equal text, call(:describe_app, "app" => APP_ID)
      end

      test "logs are the newest lines in the range, labelled by function, with exclude applied after Modal's text search" do
        batch = Proto::TaskLogsBatch.new(task_id: "ta-1", function_id: "fu-1", items: [
          Proto::TaskLogs.new(data: "CUDA out of memory\n", timestamp: Time.utc(2026, 10, 3, 9, 1).to_f, container_id: "ta-1"),
          Proto::TaskLogs.new(data: "healthcheck ok", timestamp: Time.utc(2026, 10, 3, 9, 2).to_f, container_id: "ta-1")
        ])
        ModalApi.any_instance.expects(:logs).with do |app_id, since:, upto:, limit:, source:, search_text:, function_id:, task_id:|
          app_id == APP_ID && (upto - since).round == 30.minutes && limit == 50 && source == :FILE_DESCRIPTOR_STDERR && search_text.nil? && function_id == "fu-1" &&
            task_id == ""
        end.returns([ batch ])

        text = call(:app_logs, "app" => "inference", "source" => "stderr", "function" => "generate", "exclude" => "healthcheck", "limit" => 50, "minutes" => 30)

        assert_match "1 log lines for inference", text
        assert_match "2026-10-03T09:01:00Z generate ta-1 CUDA out of memory", text
        assert_no_match "healthcheck", text
        assert_match "No function or server called nope", assert_raises(NativePack::Error) { call(:app_logs, "app" => "inference", "function" => "nope") }.message
        assert_match "source must be one of", assert_raises(NativePack::Error) { call(:app_logs, "app" => "inference", "source" => "build") }.message
      end

      test "logs narrow to one container as modal container logs does" do
        ModalApi.any_instance.expects(:logs).with { |app_id, task_id:, **| app_id == APP_ID && task_id == "ta-2" }.returns([])

        assert_match "inference container ta-2", call(:app_logs, "app" => "inference", "container" => " ta-2 ")
      end

      test "containers list newest first with their app, or that one is waiting to start, across the environment or for one app" do
        ModalApi.any_instance.stubs(:containers).with("", "main").returns([
          Proto::TaskStats.new(task_id: "ta-1", app_id: APP_ID, app_description: "inference", started_at: Time.utc(2026, 10, 3, 9).to_f),
          Proto::TaskStats.new(task_id: "ta-2", app_id: APP_ID, app_description: "inference", enqueued_at: Time.utc(2026, 10, 3, 9, 5).to_f),
          Proto::TaskStats.new(task_id: "ta-3", app_id: "ap-b", app_description: "batch", started_at: Time.utc(2026, 10, 3, 10).to_f)
        ])
        ModalApi.any_instance.stubs(:containers).with(APP_ID, "main").returns([])

        lines = call(:list_containers).lines

        assert_equal "3 containers running in main, newest first.\n", lines.first
        assert_equal "ta-3, app batch (ap-b), started 2026-10-03T10:00:00Z\n", lines.second
        assert_equal "ta-2, app inference (#{APP_ID}), waiting to start since 2026-10-03T09:05:00Z", lines.last
        assert_equal "No containers are running in inference in main.", call(:list_containers, "app" => "inference").lines.first.strip
      end

      test "a container is stopped only when it runs in the connection's environment, gracefully when asked" do
        ModalApi.any_instance.stubs(:containers).with("", "main").returns([ Proto::TaskStats.new(task_id: "ta-1", app_id: APP_ID, app_description: "inference") ])
        ModalApi.any_instance.expects(:stop_container).with("ta-1", graceful: true)
        ModalApi.any_instance.expects(:stop_container).with("ta-elsewhere", anything).never

        assert_match "Container ta-1 of inference finishes the work it holds, then stops.", call(:stop_container, "container" => "ta-1", "graceful" => true)
        assert_match "No container ta-elsewhere is running in main", assert_raises(NativePack::Error) { call(:stop_container, "container" => "ta-elsewhere") }.message
        assert_match "Say which container", assert_raises(NativePack::Error) { call(:stop_container) }.message
      end

      test "an app is stopped as modal app stop does, refused when already stopped, and names who deployed it" do
        ModalApi.any_instance.stubs(:containers).with(APP_ID, "main").returns([ Proto::TaskStats.new(task_id: "ta-1"), Proto::TaskStats.new(task_id: "ta-2") ])
        ModalApi.any_instance.expects(:stop_app).with(APP_ID).once

        assert_match "inference is stopped for good, and the 2 containers it ran are ending.", call(:stop_app, "app" => "inference")
        owner = @pack.owner_of("stop_app", environment_row: @row, arguments: { "app" => "inference" })
        assert_equal [ "ana", Owner::ROLE_DEPLOYED, "Modal app inference" ], [ owner.name, owner.role, owner.what ]
        assert_nil @pack.owner_of("stop_container", environment_row: @row, arguments: { "container" => "ta-1" })

        ModalApi.any_instance.stubs(:lifecycle).with(APP_ID).returns(Proto::AppLifecycle.new(app_state: :APP_STATE_STOPPED))
        assert_match "inference is already stopped", assert_raises(NativePack::Error) { call(:stop_app, "app" => "inference") }.message
      end

      test "the history is newest first with commits, and says which entries were rollbacks" do
        ModalApi.any_instance.stubs(:history).with(APP_ID).returns(Proto::AppDeploymentHistoryResponse.new(app_deployment_histories: [
          Proto::AppDeploymentHistory.new(version: 6, deployed_at: Time.utc(2026, 10, 2).to_f, deployed_by: "ana",
                                          commit_info: Proto::CommitInfo.new(commit_hash: "abcdef1234567890", branch: "main", dirty: true)),
          Proto::AppDeploymentHistory.new(version: 7, deployed_at: Time.utc(2026, 10, 3).to_f, deployed_by: "bo", deployment_type: :DEPLOYMENT_TYPE_ROLLBACK, rollback_version: 5)
        ]))

        lines = call(:deployment_history, "app" => "inference").lines

        assert_match "Latest 2 versions of inference, newest first", lines.first
        assert_equal "v7, 2026-10-03T00:00:00Z, by bo, a rollback, back to v5", lines.second.strip
        assert_equal "v6, 2026-10-02T00:00:00Z, by ana, commit abcdef123456 with uncommitted changes on main", lines.third.strip
      end

      test "the history keeps each version as data, the newest live and the rest replaced" do
        ModalApi.any_instance.stubs(:history).with(APP_ID).returns(Proto::AppDeploymentHistoryResponse.new(app_deployment_histories: [
          Proto::AppDeploymentHistory.new(version: 6, deployed_at: Time.utc(2026, 10, 2).to_f, tag: "release-6",
                                          commit_info: Proto::CommitInfo.new(commit_hash: "abcdef1234567890", branch: "main")),
          Proto::AppDeploymentHistory.new(version: 7, deployed_at: Time.utc(2026, 10, 3).to_f)
        ]))

        result = @pack.call("deployment_history", environment_row: @row, arguments: { "app" => "inference" })
        live, replaced = Capabilities::Deploys.deploys_of(result)

        assert_match "v7, 2026-10-03T00:00:00Z", result["content"].sole["text"]
        assert_equal [ "v7", nil, nil, Capabilities::History::SUCCEEDED, true, Time.utc(2026, 10, 3) ],
                     [ live.version, live.commit, live.tag, live.status, live.live, live.finished_at ]
        assert_equal [ "v6", "abcdef1234567890", "main", "release-6", false, Time.utc(2026, 10, 2) ],
                     [ replaced.version, replaced.commit, replaced.branch, replaced.tag, replaced.live, replaced.started_at ]
      end

      test "a rollback takes v5 or 5, goes one back when left out, and says what Modal needs when it refuses" do
        answer = Proto::AppRollbackResponse.new(url: "https://modal.com/apps/acme/main/deployed/inference", server_warnings: [ Proto::Warning.new(message: "Old client.") ])
        ModalApi.any_instance.expects(:rollback).with(APP_ID, 5).twice.returns(answer)
        ModalApi.any_instance.expects(:rollback).with(APP_ID, -1).returns(answer)

        text = call(:rollback_app, "app" => "inference", "version" => "v5")
        assert_match "inference is deployed again with v5, as a new version.\nModal warned: Old client.", text
        assert_match "https://modal.com/apps/acme/main/deployed/inference", text
        call(:rollback_app, "app" => "inference", "version" => "5")
        assert_match "the version before", call(:rollback_app, "app" => "inference")
        assert_match "version must be a version number", assert_raises(NativePack::Error) { call(:rollback_app, "app" => "inference", "version" => "latest") }.message

        ModalApi.any_instance.stubs(:rollback).raises(ModalApi::Refused, "Modal answered permission denied: rollbacks need a plan")
        assert_match "Team and Enterprise plans", assert_raises(NativePack::Error) { call(:rollback_app, "app" => "inference", "version" => "v4") }.message
      end

      test "a change to an app that is not deployed is refused before anything is sent, as Modal's CLI does" do
        ModalApi.any_instance.stubs(:lifecycle).with(APP_ID).returns(Proto::AppLifecycle.new(app_state: :APP_STATE_STOPPED))
        ModalApi.any_instance.expects(:rollover).never

        assert_match "inference is stopped, not deployed", assert_raises(NativePack::Error) { call(:rollover_app, "app" => "inference") }.message
      end

      test "a rollover links to the deployment Modal returns, and the autoscaler change says how long it lasts" do
        ModalApi.any_instance.stubs(:rollover).with(APP_ID).returns(Proto::AppRolloverResponse.new)
        assert_match "https://modal.com/id/#{APP_ID}", call(:rollover_app, "app" => "inference")

        ModalApi.any_instance.expects(:update_autoscaler).with("fu-1", { min_containers: 2, scaledown_window: 300 })
                .returns(Proto::AutoscalerSettings.new(min_containers: 2, scaledown_window: 300))
        text = call(:update_autoscaler, "app" => "inference", "function" => "generate", "min_containers" => 2, "scaledown_window" => "300")
        assert_match "generate in inference now scales with min_containers 2, scaledown_window 300. The next deployment of inference puts back what its code says.", text
        assert_match "Say what to change", assert_raises(NativePack::Error) { call(:update_autoscaler, "app" => "inference", "function" => "generate") }.message
        assert_match "whole number", assert_raises(NativePack::Error) { call(:update_autoscaler, "app" => "inference", "function" => "generate", "max_containers" => -1) }.message
      end

      test "an app Modal does not know is said in words that point at list_apps" do
        ModalApi.any_instance.stubs(:deployed).with("ghost", "main").returns(Proto::AppGetByDeploymentNameResponse.new)

        assert_match "No app called ghost in main. list_apps shows what there is.", assert_raises(NativePack::Error) { call(:describe_app, "app" => "ghost") }.message
      end

      test "the map holds the environment's deployed apps with their page, version and the commit they came from" do
        ModalApi.any_instance.stubs(:workspace).returns("acme")
        ModalApi.any_instance.stubs(:apps).with("main").returns([
          Proto::AppListResponse::AppListItem.new(app_id: APP_ID, description: "inference", state: :APP_STATE_DEPLOYED, n_running_tasks: 2,
                                                  metadata: Proto::AppHandleMetadata.new(lifecycle: Proto::AppLifecycle.new(version: 7))),
          Proto::AppListResponse::AppListItem.new(app_id: "ap-old", description: "scratch", state: :APP_STATE_STOPPED)
        ])
        ModalApi.any_instance.stubs(:history).with(APP_ID).returns(Proto::AppDeploymentHistoryResponse.new(app_deployment_histories: [
          Proto::AppDeploymentHistory.new(version: 7, commit_info: Proto::CommitInfo.new(commit_hash: "abc123"))
        ]))

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.sole
        assert_equal [ "modal", "acme/main", ResourceMap::KIND_SERVICE, APP_ID, "inference", "deployed", "https://modal.com/id/#{APP_ID}" ],
                     [ found.provider, found.account, found.kind, found.external_id, found.name, found.status, found.url ]
        assert_equal({ "version" => "v7", ResourceMap::INSTANCES => 2, ResourceMap::DEPLOYED_COMMIT => "abc123" }, found.details)

        ModalApi.any_instance.stubs(:history).raises(ModalApi::Error, "Modal answered internal: oops")
        snapshot = @pack.map_of(@row)
        assert_equal [ ResourceMap::Gap.new(text: "The deployment history of inference could not be read: Modal answered internal: oops.", kinds: []) ], snapshot.gaps
        assert_empty snapshot.unread_kinds
      end

      test "the health check reads the workspace, and a refusal fails it with Modal's words" do
        ModalApi.any_instance.stubs(:workspace).raises(ModalApi::Error, "Modal answered unauthenticated: bad token")

        assert_raises(NativePack::Error, "Modal answered unauthenticated: bad token") { @pack.check_health!(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
