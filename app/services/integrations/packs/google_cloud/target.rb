module Integrations
  module Packs
    class GoogleCloud < NativePack
      # The ids the map keeps are Google's own names, so a call reads where a resource is off its id with no listing: a
      # Cloud Run service's or job's, a GKE cluster's and a Cloud Deploy delivery pipeline's resource name, a Cloud SQL
      # instance's connection name (project:region:instance) and a Compute Engine instance's self link path. A pipeline's
      # stage is the pipeline's name and the target it releases to, since one target is in a pipeline at most once.
      ID_RUN = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/services/(?<name>[^/]+)\z}
      ID_MACHINE = %r{\Aprojects/(?<project>[^/]+)/zones/(?<location>[^/]+)/instances/(?<name>[^/]+)\z}
      ID_CLUSTER = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/clusters/(?<name>[^/]+)\z}
      ID_SQL = %r{\A(?<project>[^:/]+(?::[^:/]+)?):(?<location>[a-z0-9-]+):(?<name>[^:/]+)\z}
      ID_JOB = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/jobs/(?<name>[^/]+)\z}
      ID_PIPELINE = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/deliveryPipelines/(?<name>[^/]+)\z}
      ID_STAGE = %r{\Aprojects/(?<project>[^/]+)/locations/(?<location>[^/]+)/deliveryPipelines/(?<pipeline>[^/]+)/targets/(?<name>[^/]+)\z}
      IDS = {
        TYPE_RUN => ID_RUN, TYPE_MACHINE => ID_MACHINE, TYPE_CLUSTER => ID_CLUSTER, TYPE_SQL => ID_SQL, TYPE_JOB => ID_JOB,
        TYPE_PIPELINE => ID_PIPELINE, TYPE_STAGE => ID_STAGE
      }.freeze

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

        def job? = type == TYPE_JOB

        # A delivery pipeline or one of its stages.
        def deploy? = [ TYPE_PIPELINE, TYPE_STAGE ].include?(type)

        # The delivery pipeline a pipeline or stage is, by its own name.
        def pipeline = type == TYPE_STAGE ? id[ID_STAGE, :pipeline] : name

        # The stage's target, nil for a whole pipeline.
        def target_id = (name if type == TYPE_STAGE)

        def pipeline_id = "projects/#{project}/locations/#{location}/deliveryPipelines/#{pipeline}"
      end
    end
  end
end
