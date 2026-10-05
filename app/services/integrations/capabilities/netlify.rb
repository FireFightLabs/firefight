module Integrations
  module Capabilities
    # Netlify's own pack tools answer a site's deploys and status as they are, by the site's Netlify id, and a rollback
    # publishes an earlier deploy through restore_deploy (restoreSiteDeploy in netlify/open-api, swagger.yml). Netlify's
    # REST API keeps no logs or metrics, and a site has no instances to restart or scale, so those are not offered.
    module Netlify
      extend Adapter

      SUPPORTS = {
        DEPLOYS => [ ResourceMap::KIND_SITE ], STATUS => [ ResourceMap::KIND_SITE ], ROLLBACK => [ ResourceMap::KIND_SITE ]
      }.freeze
      TOOLS = { DEPLOYS => "list_deploys", STATUS => "describe_site", ROLLBACK => "restore_deploy" }.freeze
      WRAPPED = TOOLS.values.freeze
      SITE = "site".freeze
      DEPLOY = "deploy".freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        site = { SITE => resource.external_id }
        case key
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: site.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: site)
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: site.merge(DEPLOY => target(given)))
        end
      end
    end
  end
end
