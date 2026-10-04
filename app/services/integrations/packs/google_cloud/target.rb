module Integrations
  module Packs
    class GoogleCloud < NativePack
      # The ids the map keeps are Google's own names, so a call reads where a resource is off its id with no listing: a
      # Cloud Run service's and a GKE cluster's resource name, a Cloud SQL instance's connection name
      # (project:region:instance) and a Compute Engine instance's self link path.
      ID_RUN = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/services/(?<name>[^/]+)\z}
      ID_MACHINE = %r{\Aprojects/(?<project>[^/]+)/zones/(?<location>[^/]+)/instances/(?<name>[^/]+)\z}
      ID_CLUSTER = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/clusters/(?<name>[^/]+)\z}
      ID_SQL = %r{\A(?<project>[^:/]+(?::[^:/]+)?):(?<location>[a-z0-9-]+):(?<name>[^:/]+)\z}
      IDS = { TYPE_RUN => ID_RUN, TYPE_MACHINE => ID_MACHINE, TYPE_CLUSTER => ID_CLUSTER, TYPE_SQL => ID_SQL }.freeze

      # One thing the pack reaches: what it is, its id, and the project, region or zone and name the id holds.
      Target = Data.define(:type, :id, :project, :location, :name) do
        # The target an id names, or nil when it is not one of the pack's ids.
        def self.parse(id)
          text = id.to_s.strip
          IDS.each do |type, pattern|
            found = text.match(pattern)
            return new(type: type, id: text, project: found[:project], location: found[:location], name: found[:name]) if found
          end
          nil
        end

        def kind = KINDS.fetch(type)

        def run? = type == TYPE_RUN
      end
    end
  end
end
