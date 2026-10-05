require "grpc"
require "google/protobuf/empty_pb"
# protoc writes these classes from vendor/modal/modal_client.proto, so they live outside the autoloader and rubocop.
require_relative "../../../vendor/modal/modal_client_pb"

module Integrations
  # Calls to Modal with a workspace's own token, for the Modal integration. Modal publishes no REST API, so this speaks
  # the gRPC protocol of Modal's open source client (github.com/modal-labs/modal-client, Apache 2.0). It uses the service
  # modal.client.ModalClient at api.modal.com, the messages in vendor/modal/modal_client.proto, and the headers its Python
  # client sends (py/modal/client.py, _Client metadata, and py/modal/_utils/grpc_utils.py for x-modal-host). Every
  # call but AuthTokenGet carries the short lived token AuthTokenGet returns, as the client's auth token manager does.
  class ModalApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error
      include Integrations::RateLimited
    end
    class NotFound < Error; end
    # The token is fine, but Modal will not do this for it, such as a rollback on a plan without rollbacks.
    class Refused < Error; end

    Proto = ModalProto
    HOST = "api.modal.com".freeze
    ADDRESS = "#{HOST}:443".freeze
    SERVICE = "/modal.client.ModalClient".freeze
    # CLIENT_TYPE_CLIENT, the Python client, at the version this protocol was copied from (modal_version, 1.6.1).
    CLIENT_TYPE = "1".freeze
    CLIENT_VERSION = "1.6.1".freeze
    TIMEOUT = 30
    AUTH_TOKEN_GET = "AuthTokenGet".freeze
    # The most log lines one AppFetchLogs call returns, and the widest range Modal serves (py/modal/_logs.py).
    FETCH_LIMIT = 20_000
    MAX_FETCH_RANGE = 35.days

    def initialize(token_id, token_secret)
      @token_id = token_id.to_s
      @token_secret = token_secret.to_s
    end

    # The workspace the token belongs to, as Workspace.from_context reads it (py/modal/_workspace.py).
    def workspace = call("WorkspaceNameLookup", Google::Protobuf::Empty.new, Proto::WorkspaceNameLookupResponse).username

    # Apps that run, are deployed or stopped recently, in an environment or the workspace's default (modal app list).
    def apps(environment) = call("AppList", Proto::AppListRequest.new(environment_name: environment.to_s), Proto::AppListResponse).apps.to_a

    # A deployed app by its name, or the one of that name stopped most recently, as resolve_app_identifier does.
    def deployed(name, environment)
      call("AppGetByDeploymentName", Proto::AppGetByDeploymentNameRequest.new(name: name.to_s, environment_name: environment.to_s),
           Proto::AppGetByDeploymentNameResponse)
    end

    def lifecycle(app_id) = call("AppGetLifecycle", Proto::AppGetLifecycleRequest.new(app_id: app_id), Proto::AppGetLifecycleResponse).lifecycle

    # Its state, functions and servers, with each function's GPU, schedule and whether it serves the web (modal app info).
    def info(app_id) = call("AppGetInfo", Proto::AppGetInfoRequest.new(app_id: app_id), Proto::AppGetInfoResponse)

    # The newest lines in the range, at most limit, as tail_logs fetches them with an explicit start (py/modal/_logs.py).
    # source is a Proto::FileDescriptor value, unspecified for every stream.
    def logs(app_id, since:, upto:, limit:, source: :FILE_DESCRIPTOR_UNSPECIFIED, search_text: "", function_id: "")
      request = Proto::AppFetchLogsRequest.new(app_id: app_id, since: timestamp(since), until: timestamp(upto), limit: limit, source: source,
                                               search_text: search_text.to_s, function_id: function_id.to_s)
      call("AppFetchLogs", request, Proto::AppFetchLogsResponse).batches.to_a
    end

    def history(app_id)
      call("AppDeploymentHistory", Proto::AppDeploymentHistoryRequest.new(app_id: app_id), Proto::AppDeploymentHistoryResponse)
    end

    # The containers an app runs now (modal container list).
    def containers(app_id, environment)
      call("TaskList", Proto::TaskListRequest.new(app_id: app_id, environment_name: environment.to_s), Proto::TaskListResponse).tasks.to_a
    end

    # version is the one to go back to, or a negative number of versions back (modal app rollback).
    def rollback(app_id, version) = call("AppRollback", Proto::AppRollbackRequest.new(app_id: app_id, version: version), Proto::AppRollbackResponse)

    # New containers on the same version, rolling (modal app rollover).
    def rollover(app_id) = call("AppRollover", Proto::AppRolloverRequest.new(app_id: app_id), Proto::AppRolloverResponse)

    # Overrides a function's autoscaler until its app is deployed again (Function.update_autoscaler, py/modal/_functions.py).
    def update_autoscaler(function_id, settings)
      request = Proto::FunctionUpdateSchedulingParamsRequest.new(function_id: function_id, settings: Proto::AutoscalerSettings.new(**settings))
      call("FunctionUpdateSchedulingParams", request, Proto::FunctionUpdateSchedulingParamsResponse).current_settings
    end

    private

    def call(method, request, response_class)
      metadata = base_metadata
      metadata["x-modal-auth-token"] = auth_token unless method == AUTH_TOKEN_GET
      stub.request_response("#{SERVICE}/#{method}", request, request.class.method(:encode), response_class.method(:decode),
                            metadata: metadata, deadline: Time.now + TIMEOUT)
    rescue GRPC::ResourceExhausted => error
      raise RateLimited, said(error)
    rescue GRPC::NotFound => error
      raise NotFound, said(error)
    rescue GRPC::Unauthenticated => error
      raise Error, "#{said(error)}. Check the token id and secret, or create a new token in Modal's settings."
    rescue GRPC::PermissionDenied, GRPC::FailedPrecondition => error
      raise Refused, said(error)
    rescue GRPC::Unavailable, GRPC::DeadlineExceeded
      raise Error, "Modal could not be reached at #{HOST}. Try again shortly."
    rescue GRPC::BadStatus => error
      raise Error, said(error)
    end

    def auth_token
      @auth_token ||= call(AUTH_TOKEN_GET, Proto::AuthTokenGetRequest.new, Proto::AuthTokenGetResponse).token
    end

    def base_metadata
      { "x-modal-client-type" => CLIENT_TYPE, "x-modal-client-version" => CLIENT_VERSION, "x-modal-token-id" => @token_id,
        "x-modal-token-secret" => @token_secret, "x-modal-host" => HOST }
    end

    def stub = @stub ||= GRPC::ClientStub.new(ADDRESS, GRPC::Core::ChannelCredentials.new)

    def timestamp(time) = Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)

    # Modal's own words as a clause without its closing period, never the credentials, whatever came back.
    def said(error)
      details = [ @token_id, @token_secret ].reject(&:empty?).reduce(error.details.to_s) { |text, secret| text.gsub(secret, "[hidden]") }
      "Modal answered #{error.class.name.demodulize.underscore.humanize.downcase}: #{Sentence.clean(details) || 'no reason given'}"
    end
  end
end
