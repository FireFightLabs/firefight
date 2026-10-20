module Integrations
  module Capabilities
    # CircleCI's projects are on the map as pipelines, each built from its repository, read by the pack through CircleCI's
    # API (Packs::Circleci). For one it answers its runs with their workflows and jobs, how it stands, the log of a job
    # that failed, what it deployed and a rollback through the project's rollback pipeline. It also watches the
    # repositories a code host holds, answering how one's builds stand and its runs when CircleCI is named. A connection
    # to CircleCI's hosted MCP server answers how a repository stands through its list_runs alone, whose tools are listed
    # in CircleCI's docs (circleci/circleci-docs, docs/guides/modules/toolkit/pages/circleci-mcp-overview.adoc) with no
    # parameter named, so its arguments are written against the parameters the connected server reports.
    module Circleci
      extend Adapter

      PROVIDER_KEY = "circleci".freeze
      KINDS = [ ResourceMap::KIND_PIPELINE ].freeze
      SUPPORTS = { LOGS => KINDS, DEPLOYS => KINDS, STATUS => KINDS, HISTORY => KINDS, ROLLBACK => KINDS }.freeze
      OBSERVES = { STATUS => [ ResourceMap::KIND_REPOSITORY ], HISTORY => [ ResourceMap::KIND_REPOSITORY ] }.freeze
      LIST_RUNS = "list_runs".freeze
      STATUS_TOOL = "ci_status".freeze
      # list_runs comes first, since it is the one tool both the pack and the hosted server have.
      TOOLS = { STATUS => [ LIST_RUNS, STATUS_TOOL ], HISTORY => "ci_runs", LOGS => "get_job_logs", DEPLOYS => "list_deploys",
                ROLLBACK => "rollback_deploy" }.freeze
      # Every tool takes any project the token reaches, with a branch beside it, so they stay offered as they are.
      WRAPPED = [].freeze
      STREAM_BUILD = "build".freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze
      PHRASES = { LOGS => "read their build logs", STATUS => "check how their CI stands", HISTORY => "see how long their CI runs usually take",
                  ROLLBACK => "roll a deployed component back" }.freeze

      # The short vcs slugs of CircleCI's project slugs, by the host a repository's page is on (the project-slug parameter
      # of its API v2 spec, whose example is gh/CircleCI-Public/api-preview-docs, and whose vcs enum holds gh and bb). A
      # project on GitLab or behind CircleCI's GitHub App is circleci/<organization id>/<project id> instead, which the
      # hosted server's connection cannot learn. The pack's own connection takes the repository's address.
      VCS = { "github.com" => "gh", "bitbucket.org" => "bb" }.freeze
      OWNER_AND_NAME = %r{\A/([\w.\-]+/[\w.\-]+?)(\.git)?/?\z}
      # The names the hosted server's list_runs may give each argument, in the order they are tried.
      PROJECT = %w[project_slug projectSlug project slug].freeze
      BRANCH = %w[branch branch_name].freeze
      # Only the pack's own tools take a repository's address, which the pack finds the project of.
      REPOSITORY = "repository".freeze

      def self.subject(name) = "the #{name} projects on the map and the repositories they build"

      def self.phrase(key) = PHRASES.fetch(key) { Capabilities::PHRASES.fetch(key) }

      def self.logs_by_run? = true

      def self.route(key, resource, given, tool:, settings: nil)
        return repository_route(key, resource, tool) if resource.kind == ResourceMap::KIND_REPOSITORY

        project = { "project" => resource.external_id }
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: project.merge(logs_arguments(resource, given)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: project.merge(given.slice("limit").compact_blank))
        when STATUS then Route.new(tool_name: STATUS_TOOL, arguments: project)
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: project.merge(given.slice("name", "run", "limit").compact_blank))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: project.merge(deploy_of(target(given))))
        end
      end

      # A deploy as list_deploys names it, the component, the environment and the version, each after a slash, the
      # version keeping any slash of its own.
      def self.deploy_of(to)
        component, environment, version = to.split("/", 3)
        if [ component, environment, version ].any?(&:blank?)
          raise Unroutable, "Say what to roll back to as component/environment/version, as recent_deploys shows each deploy's id."
        end

        { "component" => component, "environment" => environment, "version" => version }
      end

      # A repository's builds are read through the pack's list_runs, ci_status and ci_runs, which find the repository's
      # project from its address. The hosted server's list_runs takes the project's slug, read off the address.
      def self.repository_route(key, resource, tool)
        raise Unroutable, "CircleCI answers how a repository's builds stand and its runs, and nothing else here." unless [ STATUS, HISTORY ].include?(key)
        return Route.new(tool_name: TOOLS[HISTORY], arguments: { REPOSITORY => resource.url.to_s }) if key == HISTORY
        return Route.new(tool_name: STATUS_TOOL, arguments: { REPOSITORY => resource.url.to_s }) if tool.nil? || Answers.named(tool, [ REPOSITORY ])

        project = Answers.named(tool, PROJECT)
        raise Unroutable, "CircleCI's list_runs takes its project in a way Firefight does not know yet, so ask it with CircleCI's own tools." if project.nil?

        arguments = { project => slug_of(resource) }
        branch = Answers.named(tool, BRANCH)
        default = resource.details.to_h["branch"]
        arguments[branch] = default if branch && default.present?
        Route.new(tool_name: LIST_RUNS, arguments: arguments)
      end
      private_class_method :repository_route

      def self.logs_arguments(resource, given)
        stream = given["stream"].presence || STREAM_BUILD
        unless stream == STREAM_BUILD
          raise Unroutable, "CircleCI keeps the build logs of #{resource.name}'s jobs, so stream must be #{STREAM_BUILD}. Ask the platform that runs it for the rest."
        end

        run = given[RUN_ARG].presence || given["deployment"].presence
        given.slice(*PASSED).merge("run" => run).compact_blank
      end
      private_class_method :logs_arguments

      # A repository's project slug, when CircleCI's documented form can be read off the address of its page.
      def self.slug_of(resource)
        page = URI.parse(resource.url.to_s)
        vcs = VCS[page.host.to_s.downcase]
        path = page.path.to_s[OWNER_AND_NAME, 1]
        unless vcs && path
          raise Unroutable, "#{resource.name} is on #{ResourceMap.provider_name(resource.provider)}, whose CircleCI projects are named by CircleCI's own " \
                            "ids, so ask CircleCI's list_runs with the slug circleci/<organization id>/<project id>, from the project's settings in CircleCI."
        end

        "#{vcs}/#{path}"
      rescue URI::InvalidURIError
        raise Unroutable, "#{resource.name} has no address CircleCI's project slug can be read from, so ask CircleCI's list_runs with the project's slug."
      end
      private_class_method :slug_of
    end
  end
end
