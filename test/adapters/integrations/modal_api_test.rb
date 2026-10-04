require "test_helper"

module Integrations
  class ModalApiTest < ActiveSupport::TestCase
    Proto = ModalApi::Proto

    setup do
      @api = ModalApi.new("ak-token", "as-secret")
    end

    test "a call carries the token and the short lived token Modal gives for it, fetched once, as Modal's client sends them" do
      sent = []
      GRPC::ClientStub.any_instance.stubs(:request_response).with do |path, request, _encode, _decode, metadata:, deadline:|
        sent << [ path, request, metadata, deadline ]
      end.returns(Proto::AuthTokenGetResponse.new(token: "jwt")).then.returns(Proto::AppListResponse.new(apps: [ Proto::AppListResponse::AppListItem.new(app_id: "ap-1") ]))
                       .then.returns(Proto::AppListResponse.new)

      assert_equal [ "ap-1" ], @api.apps("main").map(&:app_id)
      @api.apps("main")

      assert_equal [ "/modal.client.ModalClient/AuthTokenGet", "/modal.client.ModalClient/AppList", "/modal.client.ModalClient/AppList" ], sent.map(&:first)
      assert_equal "main", sent.second.second.environment_name
      token, list = sent.first(2).map { |each| each[2] }
      assert_equal({ "x-modal-client-type" => "1", "x-modal-client-version" => "1.6.1", "x-modal-token-id" => "ak-token",
                     "x-modal-token-secret" => "as-secret", "x-modal-host" => "api.modal.com" }, token)
      assert_equal "jwt", list["x-modal-auth-token"]
      assert sent.all? { |each| each[3] > Time.now }
    end

    test "a log read asks for the newest lines in the range, with the filters as Modal's fields" do
      GRPC::ClientStub.any_instance.stubs(:request_response).with { |path, *| path.end_with?("AuthTokenGet") }.returns(Proto::AuthTokenGetResponse.new(token: "jwt"))
      started = Time.utc(2026, 10, 3, 10, 0, 0, 500_000)
      GRPC::ClientStub.any_instance.expects(:request_response).with do |path, request, *|
        path.end_with?("AppFetchLogs") && request.app_id == "ap-1" && request.since.seconds == started.to_i && request.since.nanos == 500_000_000 &&
          request.limit == 200 && request.source == :FILE_DESCRIPTOR_STDERR && request.search_text == "boom" && request.function_id == "fu-1"
      end.returns(Proto::AppFetchLogsResponse.new(batches: [ Proto::TaskLogsBatch.new(task_id: "ta-1") ]))

      batches = @api.logs("ap-1", since: started, upto: started + 1.hour, limit: 200, source: :FILE_DESCRIPTOR_STDERR, search_text: "boom", function_id: "fu-1")

      assert_equal [ "ta-1" ], batches.map(&:task_id)
    end

    test "Modal's refusals become the integration's errors in Modal's words, and never carry the credentials" do
      GRPC::ClientStub.any_instance.stubs(:request_response).raises(GRPC::Unauthenticated.new("token ak-token / as-secret is not valid"))
      error = assert_raises(ModalApi::Error) { @api.workspace }
      assert_equal "Modal answered unauthenticated: token [hidden] / [hidden] is not valid. Check the token id and secret, or create a new token in Modal's settings.", error.message

      GRPC::ClientStub.any_instance.stubs(:request_response).raises(GRPC::ResourceExhausted.new("slow down"))
      assert_raises(ModalApi::RateLimited) { @api.workspace }
      GRPC::ClientStub.any_instance.stubs(:request_response).raises(GRPC::NotFound.new("no such environment"))
      assert_raises(ModalApi::NotFound) { @api.workspace }
      GRPC::ClientStub.any_instance.stubs(:request_response).raises(GRPC::FailedPrecondition.new("plan"))
      assert_raises(ModalApi::Refused) { @api.workspace }
      GRPC::ClientStub.any_instance.stubs(:request_response).raises(GRPC::Unavailable.new("down"))
      assert_equal "Modal could not be reached at api.modal.com. Try again shortly.", assert_raises(ModalApi::Error) { @api.workspace }.message
    end

    test "an autoscaler change sends only the settings asked for" do
      GRPC::ClientStub.any_instance.stubs(:request_response).with { |path, *| path.end_with?("AuthTokenGet") }.returns(Proto::AuthTokenGetResponse.new(token: "jwt"))
      GRPC::ClientStub.any_instance.expects(:request_response).with do |path, request, *|
        path.end_with?("FunctionUpdateSchedulingParams") && request.function_id == "fu-1" && request.settings.min_containers == 2 &&
          !request.settings.has_max_containers?
      end.returns(Proto::FunctionUpdateSchedulingParamsResponse.new(current_settings: Proto::AutoscalerSettings.new(min_containers: 2)))

      assert_equal 2, @api.update_autoscaler("fu-1", { min_containers: 2 }).min_containers
    end
  end
end
