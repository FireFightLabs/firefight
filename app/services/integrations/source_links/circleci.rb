module Integrations
  module SourceLinks
    # A list of a project's runs links to that project's pipelines page in CircleCI's app, on its registry site. CircleCI's
    # docs give the address as app.circleci.com/pipelines/<VCS>/<org>/<project> (security/pages/rename-organizations-and-repositories.adoc)
    # and show it with github and circleci as the first segment (reference/pages/outbound-webhooks-reference.adoc), the
    # long forms its API spec lists beside gh and bb. Every other tool is keyed by an id whose page needs the pipeline's
    # number too, which the call does not carry, so it gets no link.
    class Circleci
      PROVIDER = Capabilities::Circleci::PROVIDER_KEY
      NAME = "CircleCI".freeze
      LIST_RUNS = Capabilities::Circleci::TOOLS.fetch(Capabilities::STATUS)
      PIPELINES = "pipelines".freeze
      # The vcs segment of a project slug, short or long, as the app's address writes it.
      VCS = { "gh" => "github", "github" => "github", "bb" => "bitbucket", "bitbucket" => "bitbucket", "circleci" => "circleci" }.freeze
      SEGMENT = /\A[\w.\-]+\z/

      def initialize(settings)
        @site = settings.site
      end

      def link(tool_name:, arguments:, text: "")
        return unless tool_name == LIST_RUNS

        asked = arguments.to_h.stringify_keys
        slug = Capabilities::Circleci::PROJECT.filter_map { |name| asked[name].presence }.first.to_s
        vcs, organization, project, *rest = slug.split("/")
        return unless VCS.key?(vcs) && rest.empty? && [ organization, project ].all? { |part| part.to_s.match?(SEGMENT) }

        Telemetry::Link.new(provider: NAME, url: [ @site, PIPELINES, VCS.fetch(vcs), organization, project ].join("/"))
      end
    end
  end
end
