module Integrations
  # Calls to Google Cloud's REST APIs with a workspace's own service account key, for the Google Cloud integration. The
  # key signs a short lived assertion that Google trades for an access token (the JWT bearer grant Google documents for
  # service accounts), and the token is cached on the environment row until close to expiry.
  class GoogleCloudApi
    class Error < Integrations::Error; end
    class Forbidden < Error; end
    # Google answered that the resource is not there, the one answer a re-read takes as gone.
    class NotFound < Error
      include Integrations::NotFound
    end

    TOKEN_URI = "https://oauth2.googleapis.com/token".freeze
    GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer".freeze
    SCOPE = "https://www.googleapis.com/auth/cloud-platform".freeze
    TOKEN_CACHE_KEY = "google_cloud_token".freeze
    ASSERTION_LIFETIME = 1.hour
    TOKEN_REFRESH_MARGIN = 5.minutes
    SERVICE_ACCOUNT = "service_account".freeze
    FORBIDDEN = 403
    NOT_FOUND = 404
    AUDIT_PAGE_SIZE = 1000
    PAGE_LIMIT = 10
    # A zone Compute Engine could not reach, as aggregatedList marks its scope (InstancesScopedList warning code).
    UNREACHABLE = "UNREACHABLE".freeze

    # A list read across zones, with the zones Google Cloud could not reach, whose resources it holds none of. A list with
    # one is not complete.
    Reached = Data.define(:items, :complete, :unreachable) do
      def incomplete? = !complete
    end

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

    # token_cache is the ConnectionSettings the token is kept with, or nil to keep it for this client only.
    def initialize(key_text, token_cache: nil)
      @key = self.class.parse_key(key_text)
      @token_cache = token_cache
    end

    def client_email = @key["client_email"]

    # Resource Manager v1 takes the project id, as projects.get documents it.
    def project(project_id) = get("#{RESOURCE_MANAGER}/projects/#{segment(project_id)}")

    # Cloud Run's regions, from the v1 API, since the v2 API lists services one region at a time.
    def run_locations(project_id) = list("#{RUN_LOCATIONS}/projects/#{segment(project_id)}/locations", "locations")

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

    # Every zone's instances, as a Reached. aggregatedList answers a map of scopes to their instances, marks a zone it
    # could not reach with an UNREACHABLE warning, and names any it left out in unreachables (InstanceAggregatedList).
    def compute_instances(project_id)
      url = "#{COMPUTE}/projects/#{segment(project_id)}/aggregated/instances"
      unreachable = []
      read = Pages.read(max_pages: PAGE_LIMIT) do |token|
        page = get(url, "pageToken" => token)
        scopes = page["items"].to_h
        unreachable.concat(Array(page["unreachables"]), scopes.select { |_, scope| scope.to_h.dig("warning", "code") == UNREACHABLE }.keys)
        [ scopes.values.flat_map { |scope| Array(scope["instances"]) }, page["nextPageToken"] ]
      end
      reached(read.items, read.complete, unreachable)
    end

    def compute_instance(project_id, zone, name) = get(instance_path(project_id, zone, name))

    def reset_compute_instance(project_id, zone, name) = post("#{instance_path(project_id, zone, name)}/reset")

    # Every cluster in every location, which the GKE API reads through the location "-", as a Reached. missingZones are
    # zones whose clusters the list may be missing (ListClustersResponse).
    def clusters(project_id)
      body = get("#{CONTAINER}/projects/#{segment(project_id)}/locations/-/clusters")
      reached(Array(body["clusters"]), true, Array(body["missingZones"]))
    end

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

    # Log entries of the project matching a Logging query, oldest first, every page up to PAGE_LIMIT, as a Pages::Read
    # that says whether it holds all of them (entries.list, orderBy timestamp asc).
    def log_entries_since(project_id, filter)
      Pages.read(max_pages: PAGE_LIMIT) do |token|
        body = { "resourceNames" => [ "projects/#{project_id}" ], "filter" => filter, "orderBy" => "timestamp asc",
                 "pageSize" => AUDIT_PAGE_SIZE, "pageToken" => token }.compact
        page = post("#{LOGGING}/entries:list", body)
        [ Array(page["entries"]), page["nextPageToken"].presence ]
      end
    end

    # Cloud Monitoring's time series for one metric. query uses its own parameter names, such as interval.startTime.
    def time_series(project_id, query) = list("#{MONITORING}/projects/#{segment(project_id)}/timeSeries", "timeSeries", query).items

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

    # Every page of a list, up to PAGE_LIMIT pages, read from the key the API lists under, as a Pages::Read that says
    # whether it holds all of it.
    def list(url, key, query = {})
      Pages.read(max_pages: PAGE_LIMIT) do |token|
        page = get(url, query.merge("pageToken" => token))
        [ page[key], page["nextPageToken"] ]
      end
    end

    def segment(value) = Http.segment(value)

    private

    def reached(items, complete, unreachable)
      zones = unreachable.map { |zone| zone.to_s.delete_prefix("zones/") }.uniq
      Reached.new(items: items, complete: complete && zones.empty?, unreachable: zones)
    end

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
      Http.json(uri, request, error_class: Error, provider_name: "Google Cloud", refine: ->(code, _reason) { { FORBIDDEN => Forbidden, NOT_FOUND => NotFound }[code] })
    end

    def access_token
      cached = @token_cache&.credential(TOKEN_CACHE_KEY)
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
      body = Http.json(uri, request, error_class: Error, provider_name: "Google")
      raise Error, "Google answered with no access token" if body["access_token"].blank?

      @token = body["access_token"]
      @token_expires_at = body["expires_in"].to_i.seconds.from_now
      @token_cache&.store_credential!(TOKEN_CACHE_KEY, "token" => @token, "expires_at" => @token_expires_at.utc.iso8601)
      @token
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
