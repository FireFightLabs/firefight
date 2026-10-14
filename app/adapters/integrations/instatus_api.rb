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
    # A page of monitors, alerts or cron monitors, the most Instatus documents for cron monitors.
    MONITOR_LIMIT = 100
    MONITOR_STATUSES = %w[UP DOWN DEGRADED UNKNOWN].freeze
    MONITOR_TYPES = %w[HTTP].freeze
    MONITOR_LOCATIONS = %w[US_EAST_1 CA_CENTRAL_1 EU_CENTRAL_1 AP_NORTHEAST_1 AP_SOUTHEAST_2].freeze
    ALERT_TYPES = %w[INCIDENT EMAIL SMS SLACK DISCORD MICROSOFT_TEAMS PHONE_CALL WEBHOOK GOOGLE_CHAT WHATSAPP].freeze
    # Alerts whose recipient is a webhook address, which works as a password, so it is never sent or shown.
    WEBHOOK_ALERTS = %w[SLACK DISCORD MICROSOFT_TEAMS WEBHOOK GOOGLE_CHAT].freeze
    CRON_STATES = %w[ACTIVE PAUSED MUTED].freeze

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

    # Instatus's monitoring lives at paths with no version, and its lists page with page and limit inside an object that
    # says how many pages there are.
    def monitors(page_id, search: nil, status: nil)
      monitor_paged("/#{segment(page_id)}/monitors", "monitors", { "search" => search.presence, "status" => status.presence })
    end

    def create_monitor(body) = send_json(Net::HTTP::Post, "/monitors", body)

    def update_monitor(monitor_id, body) = send_json(Net::HTTP::Put, "/monitors/#{segment(monitor_id)}", body)

    def delete_monitor(monitor_id) = send_json(Net::HTTP::Delete, "/monitors/#{segment(monitor_id)}")

    def monitor_logs(monitor_id, limit:, status: nil, successful: nil)
      get("/monitors/#{segment(monitor_id)}/logs", { "limit" => limit, "page" => 1, "status" => status.presence, "isSuccessful" => successful })
    end

    def run_monitor(monitor_id, location: nil) = get("/monitors/#{segment(monitor_id)}/run", { "location" => location.presence })

    def monitor_alerts(page_id) = monitor_paged("/#{segment(page_id)}/monitor-alerts", "monitorAlerts")

    def create_monitor_alert(body) = send_json(Net::HTTP::Post, "/monitor-alerts", body)

    def update_monitor_alert(alert_id, body) = send_json(Net::HTTP::Put, "/monitor-alerts/#{segment(alert_id)}", body)

    def delete_monitor_alert(alert_id) = send_json(Net::HTTP::Delete, "/monitor-alerts/#{segment(alert_id)}")

    def create_monitor_group(body) = send_json(Net::HTTP::Post, "/monitors-groups", body)

    def update_monitor_group(group_id, body) = send_json(Net::HTTP::Put, "/monitors-groups/#{segment(group_id)}", body)

    def delete_monitor_group(group_id) = send_json(Net::HTTP::Delete, "/monitors-groups/#{segment(group_id)}")

    def add_monitors_to_group(group_id, monitor_ids) = send_json(Net::HTTP::Post, "/monitors-groups/#{segment(group_id)}/monitors", { "monitors" => monitor_ids })

    def run_monitor_group(group_id, location: nil) = get("/monitors-groups/#{segment(group_id)}/run", { "location" => location.presence })

    def cron_monitors(page_id, search: nil, status: nil)
      monitor_paged("/#{segment(page_id)}/monitors/cron", "cronMonitors", { "search" => search.presence, "status" => status.presence })
    end

    def create_cron_monitor(body) = send_json(Net::HTTP::Post, "/monitors/cron", body)

    def update_cron_monitor(cron_id, body) = send_json(Net::HTTP::Put, "/monitors/cron/#{segment(cron_id)}", body)

    def delete_cron_monitor(cron_id) = send_json(Net::HTTP::Delete, "/monitors/cron/#{segment(cron_id)}")

    def cron_logs(cron_id, limit:, important: false)
      get("/monitors/cron/#{segment(cron_id)}/logs", { "limit" => limit, "page" => 1, "importance" => (important ? "important" : nil) })
    end

    def cron_summary(cron_id) = get("/monitors/cron/#{segment(cron_id)}/summary")

    def metrics(page_id) = paged("/v1/#{segment(page_id)}/metrics")

    def metric(page_id, metric_id) = get("/v1/#{segment(page_id)}/metrics/#{segment(metric_id)}")

    def create_metric(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/metrics", body)

    def update_metric(page_id, metric_id, body) = send_json(Net::HTTP::Put, "/v1/#{segment(page_id)}/metrics/#{segment(metric_id)}", body)

    def delete_metric(page_id, metric_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/metrics/#{segment(metric_id)}")

    # points are { timestamp in milliseconds, value }.
    def add_metric_data(page_id, metric_id, points)
      send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/metrics/#{segment(metric_id)}/data", { "data" => points })
    end

    def delete_metric_data(page_id, metric_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/metrics/#{segment(metric_id)}/data")

    def teammates(page_id) = paged("/v1/#{segment(page_id)}/team")

    def add_teammate(page_id, email) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/team", { "email" => email })

    def remove_teammate(page_id, member_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/team/#{segment(member_id)}")

    def notices(page_id) = paged("/v1/#{segment(page_id)}/generic-notices")

    def create_notice(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/generic-notices", body)

    def update_notice(page_id, notice_id, body) = send_json(Net::HTTP::Put, "/v1/#{segment(page_id)}/generic-notices/#{segment(notice_id)}", body)

    def delete_notice(page_id, notice_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/generic-notices/#{segment(notice_id)}")

    def outages(page_id) = paged("/v1/#{segment(page_id)}/outages")

    def create_outage(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/outages", body)

    def update_outage(page_id, outage_id, body) = send_json(Net::HTTP::Put, "/v1/#{segment(page_id)}/outages/#{segment(outage_id)}", body)

    def delete_outage(page_id, outage_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/outages/#{segment(outage_id)}")

    def workspaces = paged("/v1/workspaces")

    def create_workspace(body) = send_json(Net::HTTP::Post, "/v1/workspaces", body)

    def delete_workspace(workspace_id) = send_json(Net::HTTP::Delete, "/v1/workspaces/#{segment(workspace_id)}")

    # Instatus documents reading and deleting audience groups at audience-groups, and making and changing them at
    # audience_groups, so each call uses the spelling documented for it.
    def audience_groups(page_id) = paged("/v1/#{segment(page_id)}/audience-groups")

    def create_audience_group(page_id, body) = send_json(Net::HTTP::Post, "/v1/#{segment(page_id)}/audience_groups", body)

    def update_audience_group(page_id, group_id, body) = send_json(Net::HTTP::Put, "/v1/#{segment(page_id)}/audience_groups/#{segment(group_id)}", body)

    def delete_audience_group(page_id, group_id) = send_json(Net::HTTP::Delete, "/v1/#{segment(page_id)}/audience-groups/#{segment(group_id)}")

    # A third party monitoring tool that opens and resolves incidents on a page, on version 3 of the API.
    def create_integration(body) = send_json(Net::HTTP::Post, "/v3/integrations", body)

    def update_integration(integration_id, body) = send_json(Net::HTTP::Put, "/v3/integrations/#{segment(integration_id)}", body)

    def delete_integration(integration_id) = send_json(Net::HTTP::Delete, "/v3/integrations/#{segment(integration_id)}")

    def routing_rules(page_id) = Array(get("/#{segment(page_id)}/routing-rules").to_h["routingRules"])

    def create_routing_rule(rule) = send_json(Net::HTTP::Post, "/routing-rules", { "routingRule" => rule })

    def update_routing_rule(rule_id, rule) = send_json(Net::HTTP::Put, "/routing-rules/#{segment(rule_id)}", { "routingRule" => rule })

    def delete_routing_rule(rule_id) = send_json(Net::HTTP::Delete, "/routing-rules/#{segment(rule_id)}")

    def escalation_policies(page_id) = Array(get("/#{segment(page_id)}/escalation-policies").to_h["escalationPolicies"])

    def create_escalation_policy(body) = send_json(Net::HTTP::Post, "/escalation-policies", body)

    def update_escalation_policy(policy_id, body) = send_json(Net::HTTP::Put, "/escalation-policies/#{segment(policy_id)}", body)

    def delete_escalation_policy(policy_id) = send_json(Net::HTTP::Delete, "/escalation-policies/#{segment(policy_id)}")

    def on_call_members(schedule_id) = get("/on-call-schedules/#{segment(schedule_id)}/members")

    def create_on_call_schedule(body) = send_json(Net::HTTP::Post, "/on-call-schedules", body)

    def update_on_call_schedule(schedule_id, body) = send_json(Net::HTTP::Put, "/on-call-schedules/#{segment(schedule_id)}", body)

    def delete_on_call_schedule(schedule_id) = send_json(Net::HTTP::Delete, "/on-call-schedules/#{segment(schedule_id)}")

    private

    def monitor_paged(path, key, query = {})
      Pages.read(max_pages: MAX_PAGES) do |number|
        number ||= 1
        body = get(path, query.merge("page" => number, "limit" => MONITOR_LIMIT))
        rows = body.is_a?(Hash) ? Array(body[key]) : []
        [ rows, (number + 1 if number < body.to_h["totalPages"].to_i) ]
      end
    end

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
