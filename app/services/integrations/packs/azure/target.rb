module Integrations
  module Packs
    class Azure < NativePack
      # A Resource Manager id, read into its subscription, resource group, resource type and name.
      ID = %r{\A/subscriptions/(?<subscription>[^/]+)/resourceGroups/(?<group>[^/]+)/providers/(?<path>.+)\z}i
      # The resource types the pack reaches, by the Resource Manager type path that ends their id.
      PATHS = {
        %r{\Amicrosoft\.web/sites/(?<name>[^/]+)\z}i => TYPE_WEB,
        %r{\Amicrosoft\.app/containerapps/(?<name>[^/]+)\z}i => TYPE_CONTAINER,
        %r{\Amicrosoft\.sql/servers/(?<server>[^/]+)/databases/(?<name>[^/]+)\z}i => TYPE_SQL,
        %r{\Amicrosoft\.dbforpostgresql/flexibleservers/(?<name>[^/]+)\z}i => TYPE_POSTGRES
      }.freeze

      # One thing the pack reaches. A web app and a function app are both sites, so type says site until the site is read.
      Target = Data.define(:type, :id, :subscription, :group, :name, :server) do
        def initialize(server: nil, **) = super

        def self.parse(id)
          found = id.to_s.strip.match(ID)
          return nil unless found

          PATHS.each do |pattern, type|
            path = found[:path].match(pattern)
            next unless path

            return new(type: type, id: id.to_s.strip, subscription: found[:subscription], group: found[:group], name: path[:name],
                       server: (path[:server] if path.names.include?("server")))
          end
          nil
        end

        def site? = type == TYPE_WEB

        def container? = type == TYPE_CONTAINER

        def database? = [ TYPE_SQL, TYPE_POSTGRES ].include?(type)
      end
    end
  end
end
