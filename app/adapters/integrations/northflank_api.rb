module Integrations
  # Read-only calls to Northflank's API with a workspace's own token, for the Northflank integration. The code sandbox
  # has its own client, since it runs on Firefight's token and creates services.
  class NorthflankApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error; end
    TOO_MANY_REQUESTS = 429

    API_ROOT = "https://api.northflank.com/v1".freeze
    PAGE_SIZE = 100

    def initialize(token)
      @token = token
    end

    def projects = list("/projects", "projects")

    def project(project_id) = get("/projects/#{segment(project_id)}")

    def services(project_id) = list("/projects/#{segment(project_id)}/services", "services")

    def addons(project_id) = list("/projects/#{segment(project_id)}/addons", "addons")

    def builds(project_id, service_id, limit:)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/build", "per_page" => limit).dig("data", "builds") || []
    end

    def service(project_id, service_id) = get("/projects/#{segment(project_id)}/services/#{segment(service_id)}")["data"] || {}

    def addon(project_id, addon_id) = get("/projects/#{segment(project_id)}/addons/#{segment(addon_id)}")["data"] || {}

    def deployments(project_id, service_id, limit:)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/deployments", "per_page" => limit).dig("data", "deployments") || []
    end

    # kind is services or addons, the two that run containers.
    def containers(project_id, kind, resource_id, limit:)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/containers", "per_page" => limit).dig("data", "containers") || []
    end

    def backups(project_id, addon_id, limit:)
      get("/projects/#{segment(project_id)}/addons/#{segment(addon_id)}/backups", "per_page" => limit).dig("data", "backups") || []
    end

    def jobs(project_id) = list("/projects/#{segment(project_id)}/jobs", "jobs")

    def job_runs(project_id, job_id, limit:)
      get("/projects/#{segment(project_id)}/jobs/#{segment(job_id)}/runs", "per_page" => limit).dig("data", "runs") || []
    end

    def build_logs(project_id, service_id, query)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/build-logs", { "queryType" => "range" }.merge(query))["data"] || []
    end

    # kind is services or addons, the two things that run and log in a project. query uses Northflank's own parameter
    # names, such as startTime and textIncludes.
    def logs(project_id, kind, resource_id, query)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/logs", { "queryType" => "range" }.merge(query))["data"] || []
    end

    def metrics(project_id, kind, resource_id, query)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/metrics", { "queryType" => "range" }.merge(query))["data"] || {}
    end

    private

    def list(path, key)
      get(path, "per_page" => PAGE_SIZE).dig("data", key) || []
    end

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = encode(query) if query.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return body if response.code.to_i.between?(200, 299)

      error = response.code.to_i == TOO_MANY_REQUESTS ? RateLimited : Error
      raise error, "Northflank answered #{response.code}: #{body.dig('error', 'message') || body['message'] || 'no reason given'}"
    rescue JSON::ParserError
      raise Error, "Northflank answered #{response.code} with something that is not JSON"
    end

    # A repeated parameter such as metricTypes is sent once per value, which is how Northflank reads a list.
    def encode(query)
      pairs = query.compact.flat_map { |name, value| Array(value).map { |each| [ name.to_s, each.to_s ] } }
      URI.encode_www_form(pairs)
    end

    def segment(value) = ERB::Util.url_encode(value.to_s)
  end
end
