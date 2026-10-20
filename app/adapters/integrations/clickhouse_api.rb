module Integrations
  # Calls to the ClickHouse Cloud API (https://api.clickhouse.cloud, its OpenAPI description at /v1) with a connection's
  # own API key, sent as HTTP Basic with the key id and secret as the API's basicAuth scheme says. Every answer comes
  # inside a result envelope, and a failure says why in its error field.
  class ClickhouseApi
    class Error < Integrations::Error; end
    # The key is wrong, or its role lacks the permission the call needs.
    class Refused < Error; end

    ROOT = "https://api.clickhouse.cloud".freeze
    REFUSALS = [ 401, 403 ].freeze

    # authorization is the Authorization header the connection holds, Basic and the key id and secret in base64.
    def initialize(authorization)
      @authorization = authorization
    end

    # One service with its state and scaling (the Service object), which a key with control-plane:service:view reads.
    def service(organization_id, service_id) = result(:get, service_path(organization_id, service_id))

    # Sets a service's replicas, memory per replica and idle scaling (ServiceReplicaScalingPatchRequest), which needs
    # control-plane:service:manage-scaling-config, and answers the service as it now stands.
    def replica_scaling(organization_id, service_id, body) = result(:patch, "#{service_path(organization_id, service_id)}/replicaScaling", body)

    # Starts or stops a service (instanceStateUpdate, ServiceStatePatchRequest's command start or stop), which needs
    # control-plane:service:manage, and answers the service as it now stands.
    def state(organization_id, service_id, command) = result(:patch, "#{service_path(organization_id, service_id)}/state", { "command" => command })

    # The organization's activities (activityGetList), each an Activity, between from and to when given, as ISO 8601.
    def activities(organization_id, from: nil, to: nil)
      query = { "from_date" => from, "to_date" => to }.compact
      Array(result(:get, "/v1/organizations/#{Http.segment(organization_id)}/activities", nil, query))
    end

    # One activity by its id (activityGet).
    def activity(organization_id, activity_id) = result(:get, "/v1/organizations/#{Http.segment(organization_id)}/activities/#{Http.segment(activity_id)}")

    private

    def service_path(organization_id, service_id) = "/v1/organizations/#{Http.segment(organization_id)}/services/#{Http.segment(service_id)}"

    def result(verb, path, body = nil, query = {})
      uri = URI.parse("#{ROOT}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      request = verb == :patch ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
      request["Authorization"] = @authorization
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      answer = Http.json(uri, request, error_class: Error, provider_name: "ClickHouse Cloud",
                                       refine: ->(code, _said) { Refused if REFUSALS.include?(code) })
      answer.is_a?(Hash) && answer.key?("result") ? answer["result"] : answer
    end
  end
end
