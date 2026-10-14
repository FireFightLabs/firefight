module Integrations
  # Calls to Instatus's REST API with a user's API key, for the Instatus integration. Every path, version, parameter and
  # field is from Instatus's API documentation (instatus.com/help/api and its pages on status pages, components,
  # incidents, incident updates, maintenances, maintenance updates, subscribers and templates), which puts each endpoint
  # on v1 or v2 one by one, so each path here names its own. The key is sent as a bearer token. Lists take page and
  # per_page, at most 100 a page, and answer a bare list, so the next page is asked for only while one comes back full.
  # Errors carry their words as { error: { code, message } }, which Http reads.
  class InstatusApi
    class Error < Integrations::Error; end
    # The key is wrong, or belongs to no user.
    class Unauthenticated < Error; end

    ROOT = "https://api.instatus.com".freeze
    PUBLIC_HOST = "instatus.com".freeze
    UNAUTHENTICATED = 401
    PER_PAGE = 100
    MAX_PAGES = 10

    COMPONENT_STATUSES = %w[OPERATIONAL UNDERMAINTENANCE DEGRADEDPERFORMANCE PARTIALOUTAGE MAJOROUTAGE].freeze
    INCIDENT_STATUSES = %w[INVESTIGATING IDENTIFIED MONITORING RESOLVED].freeze
    MAINTENANCE_STATUSES = %w[NOTSTARTEDYET INPROGRESS COMPLETED].freeze
    SUBSCRIBER_STATUSES = %w[confirmed unconfirmed unapproved].freeze
    # What happens when someone subscribes. WELCOME and NONE are on Instatus's Pro plan, reviewed the first time.
    CONFIRMATION_MODES = %w[REQUIRED WELCOME NONE].freeze

    # A page's public address is its custom domain when it has one, or its subdomain on instatus.com.
    def self.public_url(page)
      domain = page["customDomain"].to_s.strip
      return "https://#{domain}" if domain.present?

      subdomain = page["subdomain"].to_s.strip
      "https://#{subdomain}.#{PUBLIC_HOST}" if subdomain.present?
    end

    def initialize(api_key)
      @api_key = api_key
    end

    def pages = paged("/v2/pages")

    def create_page(body) = send_json(Net::HTTP::Post, "/v1/pages", body)

    def update_page(page_id, body) = send_json(Net::HTTP::Put, "/v2/#{segment(page_id)}", body)

    def delete_page(page_id) = send_json(Net::HTTP::Delete, "/v2/#{segment(page_id)}")

    def components(page_id) = paged("/v2/#{segment(page_id)}/components")

    def component(page_id, component_id) = get("/v2/#{segment(page_id)}/components/#{segment(component_id)}")

    # statuses keeps only incidents in them.
    def incidents(page_id, statuses: [])
      paged("/v1/#{segment(page_id)}/incidents", { "status" => statuses.presence&.join(",") })
    end

    def incident(page_id, incident_id) = get("/v1/#{segment(page_id)}/incidents/#{segment(incident_id)}")

    def maintenances(page_id) = paged("/v2/#{segment(page_id)}/maintenances")

    def maintenance(page_id, maintenance_id) = get("/v1/#{segment(page_id)}/maintenances/#{segment(maintenance_id)}")

    def subscribers(page_id, search: nil, status: nil)
      paged("/v2/#{segment(page_id)}/subscribers", { "search" => search.presence, "status" => status.presence })
    end

    def templates(page_id) = paged("/v1/#{segment(page_id)}/templates")

    def template(page_id, template_id) = get("/v1/#{segment(page_id)}/templates/#{segment(template_id)}")

    def create_incident(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/incidents", body)

    def update_incident(page_id, incident_id, body) = send_json(Net::HTTP::Put, incident_path(page_id, incident_id), body)

    def delete_incident(page_id, incident_id) = send_json(Net::HTTP::Delete, incident_path(page_id, incident_id))

    def add_incident_update(page_id, incident_id, body) = send_json(Net::HTTP::Post, "#{incident_path(page_id, incident_id)}/incident-updates", body)

    def edit_incident_update(page_id, incident_id, update_id, body)
      send_json(Net::HTTP::Put, "#{incident_path(page_id, incident_id)}/incident-updates/#{segment(update_id)}", body)
    end

    def delete_incident_update(page_id, incident_id, update_id)
      send_json(Net::HTTP::Delete, "#{incident_path(page_id, incident_id)}/incident-updates/#{segment(update_id)}")
    end

    def create_component(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/components", body)

    def update_component(page_id, component_id, body) = send_json(Net::HTTP::Put, "/v2/#{segment(page_id)}/components/#{segment(component_id)}", body)

    def delete_component(page_id, component_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/components/#{segment(component_id)}")

    def create_maintenance(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/maintenances", body)

    def update_maintenance(page_id, maintenance_id, body) = send_json(Net::HTTP::Put, maintenance_path(page_id, maintenance_id), body)

    def delete_maintenance(page_id, maintenance_id) = send_json(Net::HTTP::Delete, maintenance_path(page_id, maintenance_id))

    def add_maintenance_update(page_id, maintenance_id, body)
      send_json(Net::HTTP::Post, "#{maintenance_path(page_id, maintenance_id)}/maintenance-updates", body)
    end

    def edit_maintenance_update(page_id, maintenance_id, update_id, body)
      send_json(Net::HTTP::Put, "#{maintenance_path(page_id, maintenance_id)}/maintenance-updates/#{segment(update_id)}", body)
    end

    def delete_maintenance_update(page_id, maintenance_id, update_id)
      send_json(Net::HTTP::Delete, "#{maintenance_path(page_id, maintenance_id)}/maintenance-updates/#{segment(update_id)}")
    end

    def add_subscriber(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/subscribers", body)

    def remove_subscriber(page_id, subscriber_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/subscribers/#{segment(subscriber_id)}")

    private

    def incident_path(page_id, incident_id) = "/v1/#{segment(page_id)}/incidents/#{segment(incident_id)}"

    def maintenance_path(page_id, maintenance_id) = "/v1/#{segment(page_id)}/maintenances/#{segment(maintenance_id)}"

    # Up to MAX_PAGES pages of PER_PAGE, the next asked for only while a page comes back full.
    def paged(path, query = {})
      Pages.read(max_pages: MAX_PAGES) do |number|
        number ||= 1
        rows = Array(get(path, query.merge("page" => number, "per_page" => PER_PAGE)))
        [ rows, (number + 1 if rows.size == PER_PAGE) ]
      end
    end

    def get(path, query = {})
      uri = uri_of(path, query)
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_json(method, path, body = nil)
      uri = uri_of(path, {})
      request = method.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def uri_of(path, query)
      uri = URI.parse("#{ROOT}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      uri
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@api_key}"
      Http.json(uri, request, error_class: Error, provider_name: "Instatus", refine: ->(code, _said) { Unauthenticated if code == UNAUTHENTICATED })
    end

    def segment(value) = Http.segment(value)
  end
end
