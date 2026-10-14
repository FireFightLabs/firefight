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
    BULK_LIMIT = 100
    BULK_ALL = "all".freeze
    METRIC_TRANSFORMS = %w[average count max min sum].freeze
    SELF_PROVIDER = "Self".freeze

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

    def unsubscribed(page_id) = paged("/pages/#{segment(page_id)}/subscribers/unsubscribed")

    def subscriber_histogram(page_id) = get("/pages/#{segment(page_id)}/subscribers/histogram_by_state")

    # subscribers is a list of subscriber ids or :all. Statuspage takes at most BULK_LIMIT ids, and "all" only for a page
    # with fewer subscribers than that when unsubscribing.
    def unsubscribe_many(page_id, subscribers:, type: nil, state: nil, quietly: false)
      body = { "subscribers" => bulk(subscribers), "type" => type.presence, "state" => state.presence, "skip_unsubscription_notification" => quietly }.compact
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/subscribers/unsubscribe", body)
    end

    def resend_confirmations(page_id, subscribers:)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/subscribers/resend_confirmation", { "subscribers" => bulk(subscribers) })
    end

    # Takes quarantined subscribers back, the ones Statuspage stopped sending to after their messages bounced.
    def reactivate(page_id, subscribers:, type: nil)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/subscribers/reactivate", { "subscribers" => bulk(subscribers), "type" => type.presence }.compact)
    end

    def metrics_providers(page_id) = Pages.read(max_pages: 1) { [ Array(get("/pages/#{segment(page_id)}/metrics_providers")), nil ] }

    # A provider that holds no credentials, Self, whose metrics Firefight or anything else sends data to. The providers
    # that pull from Datadog, New Relic, Librato or Pingdom take that service's keys, which are never sent from here.
    def create_metrics_provider(page_id, provider)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/metrics_providers", { "metrics_provider" => provider })
    end

    def update_metrics_provider(page_id, provider_id, provider)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/metrics_providers/#{segment(provider_id)}", { "metrics_provider" => provider })
    end

    def delete_metrics_provider(page_id, provider_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/metrics_providers/#{segment(provider_id)}")

    def metrics(page_id) = paged("/pages/#{segment(page_id)}/metrics")

    def provider_metrics(page_id, provider_id) = paged("/pages/#{segment(page_id)}/metrics_providers/#{segment(provider_id)}/metrics")

    def create_metric(page_id, provider_id, metric)
      send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/metrics_providers/#{segment(provider_id)}/metrics", { "metric" => metric })
    end

    def update_metric(page_id, metric_id, metric) = send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/metrics/#{segment(metric_id)}", { "metric" => metric })

    def delete_metric(page_id, metric_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/metrics/#{segment(metric_id)}")

    # points by metric id, each a list of { timestamp in seconds, value }.
    def add_metric_data(page_id, points) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/metrics/data", { "data" => points })

    def reset_metric_data(page_id, metric_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/metrics/#{segment(metric_id)}/data")

    def page_access_users(page_id, email: nil) = paged("/pages/#{segment(page_id)}/page_access_users", { "email" => email.presence })

    def create_page_access_user(page_id, user) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/page_access_users", { "page_access_user" => user })

    def update_page_access_user(page_id, user_id, user)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/page_access_users/#{segment(user_id)}", { "page_access_user" => user })
    end

    def delete_page_access_user(page_id, user_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/page_access_users/#{segment(user_id)}")

    # what is :components or :metrics, and how :add, :replace or :remove, as Statuspage's PATCH, POST and DELETE on them.
    def change_page_access_user_access(page_id, user_id, what, how, ids)
      access_change("/pages/#{segment(page_id)}/page_access_users/#{segment(user_id)}/#{what}", "#{what.to_s.singularize}_ids", how, ids)
    end

    def page_access_groups(page_id) = paged("/pages/#{segment(page_id)}/page_access_groups")

    def create_page_access_group(page_id, group) = send_json(Net::HTTP::Post, "/pages/#{segment(page_id)}/page_access_groups", { "page_access_group" => group })

    def update_page_access_group(page_id, group_id, group)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/page_access_groups/#{segment(group_id)}", { "page_access_group" => group })
    end

    def delete_page_access_group(page_id, group_id) = send_json(Net::HTTP::Delete, "/pages/#{segment(page_id)}/page_access_groups/#{segment(group_id)}")

    def change_page_access_group_components(page_id, group_id, how, ids)
      access_change("/pages/#{segment(page_id)}/page_access_groups/#{segment(group_id)}/components", "component_ids", how, ids)
    end

    def status_embed(page_id) = get("/pages/#{segment(page_id)}/status_embed_config")

    def update_status_embed(page_id, config)
      send_json(Net::HTTP::Patch, "/pages/#{segment(page_id)}/status_embed_config", { "status_embed_config" => config })
    end

    private

    def bulk(subscribers) = subscribers == :all ? BULK_ALL : Array(subscribers)

    def access_change(path, key, how, ids)
      case how
      when :add then send_json(Net::HTTP::Patch, path, { key => ids })
      when :replace then send_json(Net::HTTP::Post, path, { key => ids })
      when :remove then send_json(Net::HTTP::Delete, path, ids)
      else raise ArgumentError, "unknown change #{how}"
      end
    end

    def group_body(name, components, description)
      { "description" => description.presence, "component_group" => { "name" => name, "components" => components } }.compact
    end

    def postmortem_path(page_id, incident_id) = "/pages/#{segment(page_id)}/incidents/#{segment(incident_id)}/postmortem"

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
