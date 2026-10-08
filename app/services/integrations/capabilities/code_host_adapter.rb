module Integrations
  module Capabilities
    # What every code host answers for the repositories it puts on the map: what was deployed from one (recent_deployments),
    # how its CI stands (ci_status), the log of its newest failed job (job_log), and its CI runs with how long each took
    # (ci_runs). A repository only has build logs, so a
    # log is asked of its builds unless the request says otherwise. A host's other tools take any repository, so none is
    # wrapped and all stay offered. A host's adapter extends this and names itself in HOST.
    module CodeHostAdapter
      include Adapter

      KINDS = [ ResourceMap::KIND_REPOSITORY ].freeze
      SUPPORTS = { LOGS => KINDS, DEPLOYS => KINDS, STATUS => KINDS, HISTORY => KINDS }.freeze
      TOOLS = { LOGS => "job_log", DEPLOYS => "recent_deployments", STATUS => "ci_status", HISTORY => "ci_runs" }.freeze
      WRAPPED = [].freeze
      STREAM_BUILD = "build".freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze
      # A repository's logs are its builds', and how it stands is how its CI does.
      PHRASES = { LOGS => "read their build logs", STATUS => "check how their CI stands", HISTORY => "see how long their CI runs usually take" }.freeze

      def subject(name) = "the repositories #{name} puts on the map"

      def phrase(key) = PHRASES.fetch(key) { Capabilities::PHRASES.fetch(key) }

      def route(key, resource, given, tool: nil, settings: nil)
        repo = { "repo" => resource.external_id }
        case key
        when LOGS
          stream = given["stream"].presence || STREAM_BUILD
          unless stream == STREAM_BUILD
            raise Unroutable, "#{self::HOST} keeps the build logs of #{resource.name}, so stream must be #{STREAM_BUILD}. Ask the platform that runs it for the rest."
          end

          Route.new(tool_name: TOOLS[LOGS], arguments: repo.merge(given.slice(*PASSED)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: repo.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: repo)
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: repo.merge(given.slice("name", "run", "limit").compact_blank))
        end
      end
    end
  end
end
