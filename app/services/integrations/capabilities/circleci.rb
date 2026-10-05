module Integrations
  module Capabilities
    # CircleCI builds the repositories a code host puts on the map, so it answers how one stands, its latest runs, by the
    # repository's CircleCI project. It answers through the hosted MCP server, whose tools are listed in CircleCI's docs
    # (circleci/circleci-docs, docs/guides/modules/toolkit/pages/circleci-mcp-overview.adoc): list_runs takes a project's
    # slug, such as gh/org/repo, and filters by branch or status. Every other tool is keyed by a run, workflow or job id
    # that only an earlier call gives, so a log is never one call and CircleCI answers no logs here. The docs do not name
    # any parameter, so the arguments are written against the parameters the connected server reports, and one it does
    # not have is never sent.
    module Circleci
      extend Adapter

      PROVIDER_KEY = "circleci".freeze
      SUPPORTS = {}.freeze
      OBSERVES = { STATUS => [ ResourceMap::KIND_REPOSITORY ] }.freeze
      TOOLS = { STATUS => "list_runs" }.freeze
      # CircleCI's tools reach every project the person follows, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze

      # The short vcs slugs of CircleCI's project slugs, by the host a repository's page is on (the project-slug parameter
      # of its API v2 spec, whose example is gh/CircleCI-Public/api-preview-docs, and whose vcs enum holds gh and bb). A
      # project on GitLab or behind CircleCI's GitHub App is circleci/<organization id>/<project id> instead, which
      # nothing on the map holds.
      VCS = { "github.com" => "gh", "bitbucket.org" => "bb" }.freeze
      OWNER_AND_NAME = %r{\A/([\w.\-]+/[\w.\-]+?)(\.git)?/?\z}
      # The names the tool may give each argument, in the order they are tried.
      PROJECT = %w[project_slug projectSlug project slug].freeze
      BRANCH = %w[branch branch_name].freeze

      def self.subject(name) = "the repositories on the map that #{name} builds"

      def self.phrase(key) = CodeHostAdapter::PHRASES.fetch(key) { PHRASES.fetch(key) }

      def self.route(key, resource, given, tool:, settings: nil)
        raise Unroutable, "CircleCI answers how a repository's builds stand, and nothing else here." unless key == STATUS

        slug = slug_of(resource)
        project = Answers.named(tool, PROJECT)
        if tool && project.nil?
          raise Unroutable, "CircleCI's list_runs takes its project in a way Firefight does not know yet, so ask it with CircleCI's own tools."
        end

        arguments = tool ? { project => slug } : {}
        branch = Answers.named(tool, BRANCH)
        default = resource.details.to_h["branch"]
        arguments[branch] = default if branch && default.present?
        Route.new(tool_name: TOOLS.fetch(STATUS), arguments: arguments)
      end

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
