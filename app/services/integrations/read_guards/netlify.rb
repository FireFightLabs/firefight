module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Netlify's API (netlify/open-api, swagger.yml), so what the guard settles is which
    # GETs answer secrets. Environment variables, an account's or a site's, answer their values (getEnvVars, getEnvVar,
    # getSiteEnvVars). A build hook's url starts a build for anyone who has it (listSiteBuildHooks, getSiteBuildHook). A
    # hook's data holds where it delivers, such as a Slack webhook address, with its signing secret (listHooksBySiteId,
    # getHook). A site's service instances hold the add-on's own configuration and credentials (listServiceInstancesForSite,
    # showServiceInstance). Each is read as its names, except a hook's or build hook's address, which keeps only its host.
    module Netlify
      extend PathReads

      REFUSED = {}.freeze
      SECRET_PATHS = %r{/env(/|\z)|/service-instances(/|\z)|/services/[^/]+/instances}
      WEBHOOK_PATHS = %r{/build_hooks(/|\z)|\A/hooks(/|\z)}
    end
  end
end
