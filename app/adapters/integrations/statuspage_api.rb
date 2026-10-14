module Integrations
  # Calls to Atlassian Statuspage's Manage API with an organization's API key, for the Statuspage integration. Every path,
  # parameter, root key and field is from Statuspage's OpenAPI document (developer.statuspage.io, Statuspage API 1.0.0).
  # The key is sent as Authorization: OAuth <key>, the scheme every sample there uses. Statuspage limits a key to one
  # request a second over a minute and answers 420 or 429 past it, and its errors carry their words under error or
  # message, which Http reads. Lists page with page and per_page, at most 100 a page, except the incident search (q,
  # limit and page) and the subscribers (limit and a page counted from 0).
  class StatuspageApi
    class Error < Integrations::Error; end
    # The key is wrong, expired or revoked.
    class Unauthenticated < Error; end
    # Statuspage's own rate limit answer besides 429.
    class Throttled < Error
      include Integrations::RateLimited
    end

    ROOT = "https://api.statuspage.io/v1".freeze
    PUBLIC_HOST = "statuspage.io".freeze
    UNAUTHENTICATED = 401
    THROTTLED = 420
    PER_PAGE = 100
    MAX_PAGES = 10

    COMPONENT_STATUSES = %w[operational under_maintenance degraded_performance partial_outage major_outage].freeze
    INCIDENT_STATUSES = %w[investigating identified monitoring resolved].freeze
    MAINTENANCE_STATUSES = %w[scheduled in_progress verifying completed].freeze
    IMPACTS = %w[none maintenance minor major critical].freeze
    SUBSCRIBER_TYPES = %w[email sms webhook slack teams integration_partner].freeze
    SUBSCRIBER_STATES = %w[active unconfirmed quarantined all].freeze

    # The incident lists Statuspage keeps, each its own path, and the search over every incident.
    INCIDENTS_ALL = "all".freeze
    INCIDENTS_UNRESOLVED = "unresolved".freeze
    INCIDENTS_SCHEDULED = "scheduled".freeze
    INCIDENTS_UPCOMING = "upcoming".freeze
    INCIDENTS_ACTIVE_MAINTENANCE = "active_maintenance".freeze
    INCIDENT_LISTS = [ INCIDENTS_UNRESOLVED, INCIDENTS_ACTIVE_MAINTENANCE, INCIDENTS_UPCOMING, INCIDENTS_SCHEDULED, INCIDENTS_ALL ].freeze

    # A page's public address is its own domain when it has one, or its Statuspage subdomain, which the API
    # gives as the label alone or as the whole host. nil when it names neither.
    def self.public_url(page)
      domain = page["domain"].to_s.strip
      return "https://#{domain}" if domain.present?

      subdomain = page["subdomain"].to_s.strip
      return if subdomain.empty?

      subdomain.include?(".") ? "https://#{subdomain}" : "https://#{subdomain}.#{PUBLIC_HOST}"
    end

    def initialize(api_key)
      @api_key = api_key
    end

    def pages = Pages.read(max_pages: 1) { [ Array(get("/pages")), nil ] }

    def page(page_id) = get("/pages/#{segment(page_id)}")

    def update_page(page_id, page) = send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}", { "page" => page })

    def components(page_id) = paged("/pages/#{segment(page_id)}/components")

    def component(page_id, component_id) = get("/pages/#{segment(page_id)}/components/#{segment(component_id)}")

    # start and finish are dates, as Statuspage reads them in the page's time zone.
    def component_uptime(page_id, component_id, start: nil, finish: nil)
      get("/pages/#{segment(page_id)}/components/#{segment(component_id)}/uptime", { "start" => start.presence, "end" => finish.presence, "skip_related_events" => "true" })
    end

    def component_groups(page_id) = paged("/pages/#{segment(page_id)}/component-groups")

    def incidents(page_id, list, query: nil)
      path = "/pages/#{segment(page_id)}/incidents"
      return paged("#{path}/#{list}") unless list == INCIDENTS_ALL

      Pages.read(max_pages: MAX_PAGES) do |number|
        number ||= 1
        rows = Array(get(path, { "q" => query.presence, "limit" => PER_PAGE, "page" => number }))
        [ rows, (number + 1 if rows.size == PER_PAGE) ]
      end
    end

    def incident(page_id, incident_id) = get("/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}")

    def postmortem(page_id, incident_id) = get("/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/postmortem")

    def templates(page_id) = paged("/pages/#{segment(page_id)}/incident_templates")

    def subscribers(page_id, type: nil, state: nil, query: nil)
      Pages.read(max_pages: MAX_PAGES) do |number|
        number ||= 0
        rows = Array(get("/pages/#{segment(page_id)}/subscribers",
                         { "q" => query.presence, "type" => type.presence, "state" => state.presence, "limit" => PER_PAGE, "page" => number }))
        [ rows, (number + 1 if rows.size == PER_PAGE) ]
      end
    end

    def subscriber_count(page_id, type: nil, state: nil)
      get("/pages/#{segment(page_id)}/subscribers/count", { "type" => type.presence, "state" => state.presence })
    end

    def incident_subscribers(page_id, incident_id) = paged("/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/subscribers")

    # A new incident, or scheduled maintenance when it carries scheduled_for and scheduled_until.
    def create_incident(page_id, incident) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/incidents", { "incident" => incident })

    # A body adds an update with it, at the status given.
    def update_incident(page_id, incident_id, incident)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}", { "incident" => incident })
    end

    def edit_incident_update(page_id, incident_id, update_id, update)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/incident_updates/#{segment(update_id)}",
                { "incident_update" => update })
    end

    def delete_incident(page_id, incident_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}")

    def create_component(page_id, component) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/components", { "component" => component })

    def update_component(page_id, component_id, component)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/components/#{segment(component_id)}", { "component" => component })
    end

    def delete_component(page_id, component_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/components/#{segment(component_id)}")

    # Statuspage takes a group's description beside the group rather than in it.
    def create_component_group(page_id, name:, components:, description: nil)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/component-groups", group_body(name, components, description))
    end

    def update_component_group(page_id, group_id, name:, components:, description: nil)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/component-groups/#{segment(group_id)}", group_body(name, components, description))
    end

    def delete_component_group(page_id, group_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/component-groups/#{segment(group_id)}")

    def draft_postmortem(page_id, incident_id, body)
      send_json(Net::HTTP::Put, postmortem_path(page_id, incident_id), { "postmortem" => { "body_draft" => body } })
    end

    def publish_postmortem(page_id, incident_id, options)
      send_json(Net::HTTP::Put, "#{postmortem_path(page_id, incident_id)}/publish", { "postmortem" => options })
    end

    def revert_postmortem(page_id, incident_id) = send_json(Net::HTTP::Put, "#{postmortem_path(page_id, incident_id)}/revert")

    def delete_postmortem(page_id, incident_id) = send_json(Net::HTTP::Delete, postmortem_path(page_id, incident_id))

    def create_template(page_id, template) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/incident_templates", { "template" => template })

    # An email alone makes an email subscriber, with an endpoint a webhook one, and a phone_country with a phone_number
    # an SMS one.
    def add_subscriber(page_id, subscriber) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/subscribers", { "subscriber" => subscriber })

    # The components a subscriber hears about, every one when none is named.
    def update_subscriber(page_id, subscriber_id, component_ids)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/subscribers/#{segment(subscriber_id)}", { "component_ids" => component_ids }.compact)
    end

    def unsubscribe(page_id, subscriber_id, quietly:)
      send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/subscribers/#{segment(subscriber_id)}", nil, { "skip_unsubscription_notification" => quietly })
    end

    def resend_confirmation(page_id, subscriber_id)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/subscribers/#{segment(subscriber_id)}/resend_confirmation")
    end

    def add_incident_subscriber(page_id, incident_id, subscriber)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/subscribers", { "subscriber" => subscriber })
    end

    def remove_incident_subscriber(page_id, incident_id, subscriber_id)
      send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/subscribers/#{segment(subscriber_id)}")
    end

    private

    def group_body(name, components, description)
      { "description" => description.presence, "component_group" => { "name" => name, "components" => components } }.compact
    end

    def postmortem_path(page_id, incident_id) = "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/postmortem"

    # Up to MAX_PAGES pages of PER_PAGE, the next asked for only while a page comes back full.
    def paged(path)
      Pages.read(max_pages: MAX_PAGES) do |number|
        number ||= 1
        rows = Array(get(path, { "page" => number, "per_page" => PER_PAGE }))
        [ rows, (number + 1 if rows.size == PER_PAGE) ]
      end
    end

    def get(path, query = {})
      uri = uri_of(path, query)
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_json(method, path, body = nil, query = {})
      uri = uri_of(path, query)
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
      request["Authorization"] = "OAuth #{@api_key}"
      Http.json(uri, request, error_class: Error, provider_name: "Statuspage", refine: lambda { |code, _said|
        { UNAUTHENTICATED => Unauthenticated, THROTTLED => Throttled }[code]
      })
    end

    def segment(value) = Http.segment(value)
  end
end
