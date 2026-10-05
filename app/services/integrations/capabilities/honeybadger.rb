module Integrations
  module Capabilities
    # Honeybadger collects the errors of what other connections run, so it answers the errors of a service on the map from
    # the Honeybadger project of the same name, through list_faults, and how a hostname stands from the uptime sites its
    # projects check, through get_project. The projects and their sites are the ones its health check listed
    # (HealthProbes::Honeybadger). The tools, their arguments (project_id, q, occurred_after, limit, order) and answers
    # (results of faults with klass, message, notices_count, last_notice_at and url, sites with state and
    # last_checked_at) are from honeybadger-io/honeybadger-mcp-server (internal/hbmcp/faults.go, projects.go,
    # helpers.go) and honeybadger-io/api-go (types.go). occurred_after takes RFC 3339 only, and the search syntax
    # (-is:resolved, -is:ignored) is Honeybadger's documented fault search.
    module Honeybadger
      extend Adapter

      PROVIDER_KEY = "honeybadger".freeze
      NAME = "Honeybadger".freeze
      SUPPORTS = {}.freeze
      OBSERVES = { STATUS => Adapter::ENDPOINT_KINDS, ERRORS => Adapter::ERROR_KINDS }.freeze
      TOOLS = { STATUS => HealthProbes::Honeybadger::GET_PROJECT, ERRORS => "list_faults" }.freeze
      # Honeybadger's tools reach every project, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      # list_faults answers at most 25 a call.
      FAULT_LIMIT = 25
      OPEN = "-is:resolved -is:ignored".freeze

      def self.subject(name) = "the services on the map named like a #{name} project, and the hostnames its uptime checks cover"

      def self.reaches?(settings, key)
        projects = HealthProbes::Honeybadger.projects(settings)
        key == STATUS ? projects.any? { |project| Array(project["sites"]).any? } : projects.any?
      end

      def self.route(key, resource, given, tool:, settings: nil)
        projects = HealthProbes::Honeybadger.projects(settings)
        key == STATUS ? status(resource, projects, tool) : errors(resource, given, projects, tool)
      end

      def self.errors(resource, given, projects, tool)
        project = projects.find { |each| each["name"].to_s.casecmp?(resource.name) }
        raise Unroutable, "No Honeybadger project is called #{resource.name}. list_projects shows the projects, and list_faults reads one by its id." unless project

        started, = Answers.range(given)
        started = Time.zone.at((started.to_i / 60) * 60) if Answers.minutes(given)
        query = [ OPEN, given["text"].present? ? given["text"].to_s.delete('"').then { |text| "\"#{text}\"" } : nil ].compact.join(" ")
        arguments = { "project_id" => project["id"], "q" => query, "occurred_after" => started.utc.iso8601, "order" => "recent",
                      "limit" => Answers.limit(given, FAULT_LIMIT) }
        Route.new(tool_name: TOOLS.fetch(ERRORS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| faults_result(resource, body, result) } })
      end

      def self.status(resource, projects, tool)
        sites = projects.flat_map { |project| Array(project["sites"]).map { |site| site.merge("project_id" => project["id"]) } }
        watching = Monitors.watching(resource, sites)
        raise Unroutable, "No Honeybadger uptime check watches #{resource.name} or a hostname the map says it serves." if watching.empty?

        project_id = watching.first["project_id"]
        ids = watching.select { |site| site["project_id"] == project_id }.map { |site| site["id"] }
        Route.new(tool_name: TOOLS.fetch(STATUS), arguments: Answers.known!(tool, { "id" => project_id }, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| sites_result(body, ids, result) } })
      end

      def self.faults_result(resource, body, result)
        faults = Array(body["results"]).select { |fault| fault.is_a?(Hash) && fault["id"] }
        return if faults.empty?

        shown = faults.map do |fault|
          [ "#{fault['klass']}: #{fault['message'].to_s.truncate(200)}", "#{fault['notices_count'].to_i} times", ("last #{fault['last_notice_at']}" if fault["last_notice_at"]),
            (fault["environment"] if fault["environment"].present?), fault["url"].presence ].compact.join(", ")
        end
        more = body.dig("links", "next").present? ? " There are more, so narrow the range or the text to see others." : ""
        Answers.presented(result, "#{faults.size} unresolved errors in #{resource.name}'s Honeybadger project, latest first.#{more}\n#{shown.join("\n")}")
      end

      # Only the sites that check the resource, never the rest of the project, which carries its API key.
      def self.sites_result(body, ids, result)
        sites = Array(body["sites"]).select { |site| site.is_a?(Hash) && ids.include?(site["id"]) }
        return if sites.empty?

        shown = sites.map { |site| "#{site['name']} (#{site['url']}): #{site['state']}#{", last checked #{site['last_checked_at']}" if site['last_checked_at']}#{' (paused)' if site['active'] == false}" }
        Answers.presented(result, "Honeybadger uptime checks of #{body['name']}:\n#{shown.join("\n")}")
      end

      private_class_method :errors, :status, :faults_result, :sites_result
    end
  end
end
