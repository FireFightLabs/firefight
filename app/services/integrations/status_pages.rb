module Integrations
  # Reads an outside system's public status page (Upstream), so a problem that sits with a provider is told apart from
  # one in the team's own code. A page that publishes the Statuspage summary is read as that JSON, from the address the
  # registry names. Any other page is read through Firefight's web reading (WebLookup). Both reach only a public page and
  # carry nothing of the workspace's. The caller authorizes each read as a web read, so the ledger holds it.
  module StatusPages
    class Error < Integrations::Error; end

    READ_TIMEOUT = 8
    # A page read moments ago is read again only after this, so ten failing log searches in a minute ask once.
    CACHED_FOR = 1.minute
    PAGE_LIMIT = 6_000
    UPDATE_LIMIT = 300
    SHOWN = 5
    USER_AGENT = "Firefight status check".freeze

    OPERATIONAL = "operational".freeze
    DEGRADED = "degraded".freeze
    OUTAGE = "outage".freeze
    MAINTENANCE = "maintenance".freeze
    # Read from a page, whose words say how it stands.
    UNKNOWN = "unknown".freeze
    STATES = [ OPERATIONAL, DEGRADED, OUTAGE, MAINTENANCE, UNKNOWN ].freeze
    # The summary's overall indicator in Firefight's words (Statuspage, status API, Status indicators).
    INDICATORS = { "none" => OPERATIONAL, "minor" => DEGRADED, "major" => OUTAGE, "critical" => OUTAGE, "maintenance" => MAINTENANCE }.freeze
    # A component that works, and maintenance going on now, in the summary's own words.
    COMPONENT_WORKING = "operational".freeze
    MAINTENANCE_UNDER_WAY = "in_progress".freeze

    # One incident the provider has open, with its latest update.
    Incident = Data.define(:name, :status, :impact, :updated_at, :url, :latest)
    # What a page said when it was read. affected names components that are not fully working, with how. text is a
    # page's own words, for one read as a web page.
    Reading = Data.define(:entry, :state, :headline, :incidents, :affected, :maintenance, :text, :read_at) do
      def initialize(incidents: [], affected: [], maintenance: [], text: nil, **) = super

      def url = entry.status_page.url

      def trouble? = [ DEGRADED, OUTAGE ].include?(state) || incidents.any?
    end

    module_function

    # Raises Error when the page could not be read, and WebSearch errors for one read through web reading.
    def read(entry)
      page = entry.status_page
      raise Error, "#{entry.name} has no status page Firefight knows." unless page

      page.statuspage? ? summary(entry) : page_reading(entry)
    end

    def summary(entry)
      body = Rails.cache.fetch([ "status_pages", entry.key ], expires_in: CACHED_FOR) { fetch(entry.status_page.summary_url, entry) }
      reading_of(entry, body)
    end

    def fetch(url, entry)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/json"
      Http.json(uri, request, error_class: Error, provider_name: "#{entry.name}'s status page", read_timeout: READ_TIMEOUT)
    end

    def reading_of(entry, body)
      status = body["status"].to_h
      affected = Array(body["components"]).reject { |component| component["group"] == true || component["status"].to_s == COMPONENT_WORKING }
                                           .map { |component| "#{component['name']} (#{component['status'].to_s.tr('_', ' ')})" }
      incidents = Array(body["incidents"]).map do |incident|
        latest = Array(incident["incident_updates"]).first.to_h["body"]
        Incident.new(name: incident["name"].to_s, status: incident["status"].to_s, impact: incident["impact"].to_s,
                     updated_at: Telemetry.parse_time(incident["updated_at"]), url: incident["shortlink"].presence || entry.status_page.url,
                     latest: latest.to_s.squish.truncate(UPDATE_LIMIT).presence)
      end
      maintenance = Array(body["scheduled_maintenances"]).select { |each| each["status"].to_s == MAINTENANCE_UNDER_WAY }.map { |each| each["name"].to_s }
      Reading.new(entry: entry, state: INDICATORS.fetch(status["indicator"].to_s, UNKNOWN), headline: status["description"].to_s.presence || "No overall status given",
                  incidents: incidents, affected: affected, maintenance: maintenance, read_at: Time.current)
    end

    def page_reading(entry)
      text = Rails.cache.fetch([ "status_pages", entry.key, "page" ], expires_in: CACHED_FOR) { WebLookup.read(entry.status_page.url) }
      Reading.new(entry: entry, state: UNKNOWN, headline: "Read from the page", text: text.truncate(PAGE_LIMIT), read_at: Time.current)
    end

    # What a reading says, for a model or a person, with the page's address so it can be checked.
    def words(reading)
      lead = "#{reading.entry.name} status, from #{reading.url}, read at #{reading.read_at.utc.iso8601}"
      return "#{lead}. What the page says:\n#{reading.text}" if reading.text

      lines = [ "#{lead}: #{reading.headline}." ]
      if reading.incidents.any?
        lines << "Open incidents:"
        lines.concat(reading.incidents.first(SHOWN).map { |incident| incident_line(incident) })
      end
      lines << "Not fully working: #{reading.affected.first(SHOWN * 2).join(', ')}." if reading.affected.any?
      lines << "Maintenance under way: #{reading.maintenance.join(', ')}." if reading.maintenance.any?
      lines << "Nothing is reported wrong." unless reading.trouble? || reading.maintenance.any?
      lines.join("\n")
    end

    def incident_line(incident)
      said = [ incident.status, ("#{incident.impact} impact" if incident.impact.present? && incident.impact != "none"),
               ("updated #{incident.updated_at.utc.iso8601}" if incident.updated_at) ].compact.join(", ")
      latest = incident.latest ? " #{incident.latest}" : ""
      "- #{incident.name} (#{said}).#{latest} #{incident.url}"
    end
  end
end
