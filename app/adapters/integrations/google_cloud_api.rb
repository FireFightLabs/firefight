module Integrations
  # Calls to Google Cloud's REST APIs with a workspace's own service account key, for the Google Cloud integration. The
  # key signs a short lived assertion that Google trades for an access token (the JWT bearer grant Google documents for
  # service accounts), and the token is cached on the environment row until close to expiry.
  class GoogleCloudApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error; end
    class Forbidden < Error; end

    TOKEN_URI = "https://oauth2.googleapis.com/token".freeze
    GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer".freeze
    SCOPE = "https://www.googleapis.com/auth/cloud-platform".freeze
    TOKEN_CACHE_KEY = "google_cloud_token".freeze
    ASSERTION_LIFETIME = 1.hour
    TOKEN_REFRESH_MARGIN = 5.minutes
    SERVICE_ACCOUNT = "service_account".freeze
    TOO_MANY_REQUESTS = 429
    FORBIDDEN = 403
    PAGE_LIMIT = 10

    RESOURCE_MANAGER = "https://cloudresourcemanager.googleapis.com/v1".freeze
    RUN = "https://run.googleapis.com/v2".freeze
    # Cloud Run's v2 API lists services one region at a time and has no list of regions, so the v1 API names them.
    RUN_LOCATIONS = "https://run.googleapis.com/v1".freeze
    LOGGING = "https://logging.googleapis.com/v2".freeze
    MONITORING = "https://monitoring.googleapis.com/v3".freeze
    SQL_ADMIN = "https://sqladmin.googleapis.com/v1".freeze
    COMPUTE = "https://compute.googleapis.com/compute/v1".freeze
    CONTAINER = "https://container.googleapis.com/v1".freeze
    CLOUD_ASSET = "https://cloudasset.googleapis.com/v1".freeze
    ERROR_REPORTING = "https://clouderrorreporting.googleapis.com/v1beta1".freeze

    # The key file's fields, as Google writes them in a service account key.
    def self.parse_key(text)
      key = JSON.parse(text.to_s)
      raise Error, "This is not a service account key. Paste the whole JSON key file Google gave you." unless key.is_a?(Hash) && key["type"] == SERVICE_ACCOUNT
      raise Error, "The key has no client_email or private_key. Paste the whole JSON key file." if key["client_email"].blank? || key["private_key"].blank?

      key
    rescue JSON::ParserError
      raise Error, "The key is not JSON. Paste the whole JSON key file Google gave you."
    end

    # token_cache is the environment row the token is cached on, or nil to keep it for this client only.
    def initialize(key_text, token_cache: nil)
      @key = self.class.parse_key(key_text)
      @token_cache = token_cache
    end

    def client_email = @key["client_email"]

    # Resource Manager v1 takes the project id, as projects.get documents it.
    def project(project_id) = get("#{RESOURCE_MANAGER}/projects/#{segment(project_id)}")

    # Cloud Run's regions, from the v1 API, since the v2 API lists services one region at a time.
    def run_locations(project_id) = list("#{RUN_LOCATIONS}/projects/#{segment(project_id)}/locations", "locations").filter_map { |location| location["locationId"] }

    def run_services(project_id, location) = list("#{RUN}/projects/#{segment(project_id)}/locations/#{segment(location)}/services", "services")

    def run_service(project_id, location, name) = get(run_path(project_id, location, name))

    def run_revisions(project_id, location, name, limit:)
      Array(get("#{run_path(project_id, location, name)}/revisions", "pageSize" => limit)["revisions"])
    end

    # A change to a service, which Cloud Run answers with a long-running operation.
    def update_run_service(project_id, location, name, body, update_mask: nil)
      patch(run_path(project_id, location, name), body, "updateMask" => update_mask)
    end

    def sql_instances(project_id) = list("#{SQL_ADMIN}/projects/#{segment(project_id)}/instances", "items")

    def sql_instance(project_id, name) = get("#{SQL_ADMIN}/projects/#{segment(project_id)}/instances/#{segment(name)}")

    def restart_sql_instance(project_id, name) = post("#{SQL_ADMIN}/projects/#{segment(project_id)}/instances/#{segment(name)}/restart")

    # Every zone's instances. aggregatedList answers a map of scopes to their instances, so it is read page by page here.
    def compute_instances(project_id)
      url = "#{COMPUTE}/projects/#{segment(project_id)}/aggregated/instances"
      instances = []
      token = nil
      PAGE_LIMIT.times do
        page = get(url, "pageToken" => token)
        instances.concat(page["items"].to_h.values.flat_map { |scope| Array(scope["instances"]) })
        token = page["nextPageToken"].presence
        break unless token
      end
      instances
    end

    def compute_instance(project_id, zone, name) = get(instance_path(project_id, zone, name))

    def reset_compute_instance(project_id, zone, name) = post("#{instance_path(project_id, zone, name)}/reset")

    # Every cluster in every location, which the GKE API reads through the location "-".
    def clusters(project_id) = Array(get("#{CONTAINER}/projects/#{segment(project_id)}/locations/-/clusters")["clusters"])

    def cluster(project_id, location, name) = get("#{CONTAINER}/projects/#{segment(project_id)}/locations/#{segment(location)}/clusters/#{segment(name)}")

    # Log entries of the project matching a Logging query, newest first. An empty page with a next page token means Logging
    # has not finished searching, so it is followed while there is room.
    def log_entries(project_id, filter, limit:)
      entries = []
      token = nil
      PAGE_LIMIT.times do
        body = { "resourceNames" => [ "projects/#{project_id}" ], "filter" => filter, "orderBy" => "timestamp desc",
                 "pageSize" => limit - entries.size, "pageToken" => token }.compact
        page = post("#{LOGGING}/entries:list", body)
        entries.concat(Array(page["entries"]))
        token = page["nextPageToken"].presence
        break if token.nil? || entries.size >= limit
      end
      entries.first(limit)
    end

    # Cloud Monitoring's time series for one metric. query uses its own parameter names, such as interval.startTime.
    def time_series(project_id, query) = list("#{MONITORING}/projects/#{segment(project_id)}/timeSeries", "timeSeries", query)

    # Error Reporting's groups of errors. query uses its own parameter names, such as serviceFilter.service.
    def error_group_stats(project_id, query)
      Array(get("#{ERROR_REPORTING}/projects/#{segment(project_id)}/groupStats", query)["errorGroupStats"])
    end

    def get(url, query = {})
      uri = URI.parse(url)
      uri.query = encode(query) if query.compact.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def post(url, body = {}, query = {}) = write(Net::HTTP::Post, url, body, query)

    def patch(url, body, query = {}) = write(Net::HTTP::Patch, url, body, query)

    # Every page of a list, up to PAGE_LIMIT pages, read from the key the API lists under.
    def list(url, key, query = {})
      items = []
      token = nil
      PAGE_LIMIT.times do
        page = get(url, query.merge("pageToken" => token))
        items.concat(Array(page[key]))
        token = page["nextPageToken"].presence
        break unless token
      end
      items
    end

    def segment(value) = ERB::Util.url_encode(value.to_s)

    private

    def run_path(project_id, location, name) = "#{RUN}/projects/#{segment(project_id)}/locations/#{segment(location)}/services/#{segment(name)}"

    def instance_path(project_id, zone, name) = "#{COMPUTE}/projects/#{segment(project_id)}/zones/#{segment(zone)}/instances/#{segment(name)}"

    def write(verb, url, body, query)
      uri = URI.parse(url)
      uri.query = encode(query) if query.compact.any?
      request = verb.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      send_request(uri, request)
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{access_token}"
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      succeeded = response.code.to_i.between?(200, 299)
      body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return body if succeeded

      reason = body.dig("error", "message") || body["message"] || "no reason given"
      error = case response.code.to_i
      when TOO_MANY_REQUESTS then RateLimited
      when FORBIDDEN then Forbidden
      else Error
      end
      raise error, "Google Cloud answered #{response.code}: #{reason}"
    rescue JSON::ParserError
      # A change Google accepted stays one it accepted, whatever came back with it.
      return {} if succeeded

      raise Error, "Google Cloud answered #{response.code} with something that is not JSON"
    end

    def access_token
      cached = @token_cache&.credentials_hash&.dig(TOKEN_CACHE_KEY)
      if cached.present?
        expires_at = Time.zone.parse(cached["expires_at"].to_s)
        return cached["token"] if expires_at && expires_at > TOKEN_REFRESH_MARGIN.from_now
      end
      return @token if @token && @token_expires_at > TOKEN_REFRESH_MARGIN.from_now

      mint_token
    end

    def mint_token
      uri = URI.parse(TOKEN_URI)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data("grant_type" => GRANT_TYPE, "assertion" => assertion)
      response = Http.request(uri, request, error_class: Error)
      body = JSON.parse(response.body.to_s.presence || "{}")
      unless response.code.to_i.between?(200, 299) && body["access_token"].present?
        raise Error, "Google refused the service account key: #{body['error_description'] || body['error'] || "HTTP #{response.code}"}"
      end

      @token = body["access_token"]
      @token_expires_at = body["expires_in"].to_i.seconds.from_now
      @token_cache&.store_credential!(TOKEN_CACHE_KEY, "token" => @token, "expires_at" => @token_expires_at.utc.iso8601)
      @token
    rescue JSON::ParserError
      raise Error, "Google answered #{response.code} with something that is not JSON"
    end

    def assertion
      now = Time.current.to_i
      key = OpenSSL::PKey::RSA.new(@key["private_key"])
      claims = { iss: @key["client_email"], scope: SCOPE, aud: TOKEN_URI, iat: now, exp: now + ASSERTION_LIFETIME.to_i }
      JWT.encode(claims, key, "RS256", { kid: @key["private_key_id"] }.compact)
    rescue OpenSSL::PKey::RSAError
      raise Error, "The key's private_key is not a valid RSA key. Paste the whole JSON key file again."
    end

    # A repeated parameter is sent once per value, which is how Google's APIs read a list.
    def encode(query)
      pairs = query.compact.flat_map { |name, value| Array(value).map { |each| [ name.to_s, each.to_s ] } }
      URI.encode_www_form(pairs)
    end
  end
end
