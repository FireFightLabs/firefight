module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Trigger.dev's management API (triggerdotdev/trigger.dev, docs/v3-openapi.yaml), so
    # what the guard settles is which GETs answer secrets. An environment's variables answer their values, a secret's
    # redacted but every other one in full (list_project_envvars_v1, retrieve_project_envvar_v1), so they are read as
    # names. Nothing else a GET reaches answers a credential.
    module TriggerDev
      extend PathReads

      REFUSED = {}.freeze
      SECRET_PATHS = %r{/envvars(/|\z)}
    end
  end
end
