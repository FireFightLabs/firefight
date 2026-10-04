module Integrations
  module Capabilities
    # Sentry collects the errors and releases of what other connections run, so it answers errors and deploys for a
    # resource on the map by the Sentry project of the same name. Every tool, parameter and answer here is read from
    # Sentry's own server, getsentry/sentry-mcp, under packages/mcp-core/src. Errors go through search_issues, from
    # tools/catalog/search-issues.ts. Releases go through execute_sentry_tool running find_releases, from
    # tools/catalog/find-releases.ts, since tools/surfaces.ts keeps find_releases in the catalog rather than listing it.
    # Every tool needs the organization, which the server takes from the connection's address, /mcp/<organization> or
    # /mcp/<organization>/<project>, as docs/specs/subpath-constraints.md gives it. The connect form builds that address
    # from the organization and project it asks.
    module Sentry
      extend Adapter

      PROVIDER_KEY = "sentry".freeze
      NAME = "Sentry".freeze
      SUPPORTS = {}.freeze
      # Sentry's releases are of what sends it errors, so both read the same kinds.
      OBSERVES = { ERRORS => Adapter::ERROR_KINDS, DEPLOYS => Adapter::ERROR_KINDS }.freeze
      SEARCH_ISSUES = "search_issues".freeze
      EXECUTE = "execute_sentry_tool".freeze
      FIND_RELEASES = "find_releases".freeze
      TOOLS = { ERRORS => SEARCH_ISSUES, DEPLOYS => EXECUTE }.freeze
      # Sentry's tools reach every project in the organization, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze

      # The windows search_issues takes, in minutes. lastSeen in the query narrows the one sent to the minute.
      PERIODS = { "24h" => 24 * 60, "7d" => 7 * 24 * 60, "14d" => 14 * 24 * 60, "30d" => 30 * 24 * 60, "90d" => 90 * 24 * 60 }.freeze
      ISSUE_LIMIT = 100
      # find_releases answers at most this many, newest first.
      RELEASE_LIMIT = 25
      # A project slug as the server accepts one, from utils/slug-validation.ts.
      SLUG = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}\z/
      # Sentry's server holds a session to the organization and project its address names, so the address says which,
      # whether the connect form built it from the organization and project asked or it was pasted whole.
      SCOPE_PATH = %r{\A/mcp(?:/(?<organization>[^/]+)(?:/(?<project>[^/]+))?)?/?\z}

      # The organization and project the connection is held to.
      Scope = Data.define(:organization, :project)

      def self.scope_of(settings)
        found = URI.parse(settings&.server_url.to_s).path.to_s.match(SCOPE_PATH)
        Scope.new(organization: found&.[](:organization), project: found&.[](:project))
      rescue URI::InvalidURIError
        Scope.new(organization: nil, project: nil)
      end

      def self.route(key, resource, given, tool:, settings: nil)
        project = project_of(resource, scope_of(settings))
        key == ERRORS ? errors(given, project) : releases(resource, given, project)
      end

      # The project a resource is, by its name. A connection held to one project answers only for that one, and the
      # server fills in the project itself, so it is not sent.
      def self.project_of(resource, scope)
        unless scope.organization
          raise Unroutable, "This Sentry connection was made without an organization, so Firefight cannot tell which organization's " \
                            "#{resource.name} to read. Ask with Sentry's own tools, or have an admin connect Sentry again and give its organization."
        end
        if scope.project
          return if scope.project.casecmp?(resource.name)

          raise Unroutable, Sentence.ended("This Sentry connection only reads the #{scope.project} project, not #{resource.name}")
        end
        unless resource.name.match?(SLUG)
          raise Unroutable, "#{resource.name} cannot be the name of a Sentry project, so ask with Sentry's own tools for the project it reports to."
        end

        resource.name
      end

      # The project's issues seen in the range, last seen first, each one kind of error with its count. The server's
      # answer already links each issue and the search to their pages in Sentry. message matches any part of an error's
      # message, as Sentry's search docs give it in getsentry/sentry-docs, docs/concepts/search/searchable-properties/issues.mdx.
      def self.errors(given, project)
        seen, period = window(given)
        filters = [ seen, ("message:\"#{given['text'].to_s.delete('"')}\"" if given["text"].present?) ].compact
        arguments = { "query" => filters.join(" "), "sort" => "date", "period" => period }
        arguments["projectSlugOrId"] = project if project
        limit = Answers.limit(given, ISSUE_LIMIT, default: nil)
        arguments["limit"] = limit if limit
        Route.new(tool_name: SEARCH_ISSUES, arguments: arguments)
      end

      # Minutes alone go as Sentry's relative time, lastSeen:-30m, so the same request reads the same each time
      # and an approved call matches its retry. A start or end is sent as a comparison on the time, in ISO 8601. Both
      # forms are in the same search docs, and the windows are search_issues' own period values.
      def self.window(given)
        if (minutes = Answers.minutes(given))
          return [ "lastSeen:-#{minutes}m", period_for(minutes) ]
        end

        started, ended = Answers.range(given)
        back = ((Time.current - started) / 60).ceil
        raise Unroutable, "Sentry searches issues seen in the last 90 days, so start must be within them." if back > PERIODS.values.max

        [ "lastSeen:>=#{started.utc.iso8601} lastSeen:<=#{ended.utc.iso8601}", period_for(back) ]
      end

      def self.period_for(minutes) = PERIODS.find { |_name, length| minutes <= length }&.first || PERIODS.keys.last

      def self.releases(resource, given, project)
        limit = Answers.limit(given, RELEASE_LIMIT)
        arguments = { "name" => FIND_RELEASES, "arguments" => project ? { "projectSlug" => project } : {} }
        Route.new(tool_name: EXECUTE, arguments: arguments, present: ->(result) { releases_result(resource, result, limit) })
      end

      # find_releases answers as structured content, with the same JSON as its text for clients that read only text.
      # It names each release by its short version, which is not always the one its page is under, so the page comes
      # from get_release_details, whose answer carries it.
      def self.releases_result(resource, result, limit)
        Answers.read(result, NAME) do |data|
          next unless data.is_a?(Hash) && data["releases"].is_a?(Array)

          rows = data["releases"].first(limit).map { |release| release_line(release) }
          if rows.empty?
            next Telemetry.result(Sentence.ended("Sentry has no releases for #{resource.name}"), link: nil).merge(Telemetry::STRUCTURED => { "releases" => [] })
          end

          more = data["hasMore"] || data["releases"].size > limit ? " Older releases were not listed." : ""
          Answers.presented(result, "Latest #{rows.size} releases of #{resource.name} in Sentry, newest first.#{more} Sentry does not roll back, " \
                                    "so a rollback goes through the platform that runs #{resource.name}. #{EXECUTE} running get_release_details " \
                                    "with a version gives that release's deploys, commits and page in Sentry, to give the person with what " \
                                    "you found.\n#{rows.join("\n")}")
        end
      end

      def self.release_line(release)
        deploy = release["lastDeploy"] || {}
        commit = release["lastCommit"] || {}
        deployed = deploy["dateFinished"] || deploy["dateStarted"]
        [
          "release #{release['version']}", "created #{release['dateCreated']}", ("released #{release['dateReleased']}" if release["dateReleased"]),
          ("last deployed to #{deploy['environment'] || 'an unnamed environment'}#{" at #{deployed}" if deployed}" if deploy["id"]),
          ("commit #{commit['id'].to_s.first(12)}#{" by #{commit['author']}" if commit['author']} \"#{commit['message'].to_s.lines.first.to_s.strip}\"" if commit["id"]),
          "#{release['newIssues'].to_i} new issues", ("first event #{release['firstEvent']}" if release["firstEvent"])
        ].compact.join(", ")
      end
      private_class_method :project_of, :errors, :window, :period_for, :releases, :releases_result, :release_line
    end
  end
end
