module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Render's public API (api-docs.render.com/openapi/render-public-api-1.json), so
    # what the guard settles is which GETs answer secrets. A datastore's connection info is nothing but its password and
    # addresses that carry it, and a Postgres export answers links that download the data for anyone who has them, so
    # neither is read. Environment variables and secret files, a service's or an environment group's, and registry
    # credentials are read as their names.
    module Render
      extend PathReads

      REFUSED = {
        %r{\A/(postgres|key-value|redis)/[^/]+/connection-info\z} =>
          "A datastore's connection info is its password and the addresses that carry it, so a read never fetches it. " \
          "Its plan, status and region are on the datastore itself.",
        %r{\A/postgres/[^/]+/export} =>
          "A Postgres export answers links that download the database for anyone who has them, so a read never fetches it. " \
          "Its backups are listed under the database in Render's dashboard."
      }.freeze
      SECRET_PATHS = %r{/(env-vars|secret-files)(/|\z)|\A/env-groups/[^/]+\z|\A/registrycredentials}
    end
  end
end
