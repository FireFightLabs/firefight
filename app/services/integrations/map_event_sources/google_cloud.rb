module Integrations
  module MapEventSources
    # Google Cloud's changes, read every five minutes from each project's Admin Activity audit log with the connection's own
    # key (Cloud Logging entries.list, logging.googleapis.com/v2). Admin Activity logs are always written, cost nothing and
    # are readable with the Logs Viewer role the connection already asks for (Cloud Audit Logs overview, Admin Activity
    # audit logs, and Access control with IAM, roles/logging.viewer). Pushing them instead would need a log sink, a Pub/Sub
    # topic and a push subscription made in the project, which a key that only reads cannot make, so reading the log asks
    # nothing more of an admin. Each entry names the service that wrote it (protoPayload.serviceName), the method
    # (protoPayload.methodName), the resource (protoPayload.resourceName and the monitored resource's labels) and its own
    # insertId, which is unique per entry (LogEntry, insertId).
    class GoogleCloud < MapEventSource
      RUN = "run.googleapis.com".freeze
      SQL = "cloudsql.googleapis.com".freeze
      COMPUTE = "compute.googleapis.com".freeze
      GKE = "container.googleapis.com".freeze
      DEPLOY = "clouddeploy.googleapis.com".freeze
      SERVICES = [ RUN, SQL, COMPUTE, GKE, DEPLOY ].freeze
      # The monitored resource a Cloud Run job's entries are written on (Cloud Run, Audit logging).
      RUN_JOB = "cloud_run_job".freeze
      # The project's Admin Activity log, by the name Cloud Audit Logs gives it.
      ACTIVITY_LOG = "projects/%<project>s/logs/cloudaudit.googleapis.com%%2Factivity".freeze
      # Each read starts this far before the last one ended, so an entry Logging stored late is still read. One read twice
      # carries the same insertId and is kept once.
      OVERLAP = 10.minutes
      REMOVED = /delete/i
      ADDED = /create|insert/i

      class << self
        # Nothing is sent to the connection's address, so nothing that arrives there is Google's.
        def verify(**) = false

        def events(_payload, headers:) = []

        # Each project's entries after its own cursor, oldest first, as events about the Cloud Run service or job, Cloud
        # SQL instance, Compute Engine instance, GKE cluster or Cloud Deploy pipeline each names. A project's first read starts from now. A read cut
        # short continues from its last entry.
        def poll(row, since:)
          api = api(row)
          poll_each_scope(row, since: since) { |project, cursor| poll_project(api, project, cursor) }
        end

        def limits = "Firefight reads Google Cloud's audit log every 5 minutes, so a change reaches the map within about 6 minutes. " \
                     "A Cloud Run job's execution or a Cloud Deploy rollout finishing is not in the audit log, so a watch on one reads it each minute."

        private

        # One project's entries after since.
        def poll_project(api, project, since)
          now = Time.current
          return MapEventSource::Polled.new(events: [], cursor: now.utc.iso8601(6)) if since.blank?

          read = api.log_entries_since(project, filter(project, Time.iso8601(since) - OVERLAP))
          events = read.items.filter_map { |entry| event_of(project, entry) }
          # Cloud Logging may answer pages with no entries while it is still searching, which leaves the cursor where it was.
          cursor = if read.complete then now
          elsif read.items.any? then Time.iso8601(read.items.last["timestamp"].to_s)
          else Time.iso8601(since)
          end
          MapEventSource::Polled.new(events: events, cursor: cursor.utc.iso8601(6))
        end

        def filter(project, from)
          services = SERVICES.map { |service| "\"#{service}\"" }.join(" OR ")
          "logName=\"#{format(ACTIVITY_LOG, project: project)}\" AND timestamp>=\"#{from.utc.iso8601(6)}\" AND protoPayload.serviceName=(#{services})"
        end

        # The resource an entry is about, with the id the pack keeps for it on the map, or nil for anything else.
        def event_of(project, entry)
          payload = entry["protoPayload"].to_h
          labels = entry.dig("resource", "labels").to_h
          name = payload["resourceName"].to_s
          kind, id = case payload["serviceName"]
          when RUN then entry.dig("resource", "type") == RUN_JOB || name.match?(JOB_NAME) ? job_resource(project, labels, name) : run_resource(project, labels, name)
          when SQL then sql_resource(project, labels, name)
          when COMPUTE then machine_resource(project, labels, name)
          when GKE then cluster_resource(project, labels, name)
          when DEPLOY then deploy_resource(project, name)
          end
          return unless kind

          method = payload["methodName"].to_s
          # A call on something inside a resource, such as an execution of a job or a rollout of a pipeline, changes the
          # resource, whatever it did to the thing inside.
          action = if within?(name) then ResourceMap::Event::UPDATED
          elsif method.match?(REMOVED) then ResourceMap::Event::REMOVED
          elsif method.match?(ADDED) then ResourceMap::Event::ADDED
          else ResourceMap::Event::UPDATED
          end
          ResourceMap::Event.new(id: entry["insertId"], at: time(entry["timestamp"]), action: action,
                                 scope: ResourceMap::Scope.new(account: project, kind: kind, external_id: id))
        end

        # A Cloud Run service's entries are on cloud_run_revision with its service_name and location (Cloud Run, Audit
        # logging), and a v2 call's resource name holds both too.
        def run_resource(project, labels, name)
          service = labels["service_name"].presence || name[%r{/services/([^/]+)}, 1]
          location = labels["location"].presence || name[%r{locations/([^/]+)}, 1]
          [ ResourceMap::KIND_SERVICE, "projects/#{project}/locations/#{location}/services/#{service}" ] if service && location
        end

        JOB_NAME = %r{/jobs/[^/]+}
        WITHIN = %r{/(?:jobs/[^/]+/executions|deliveryPipelines/[^/]+/releases)/}

        def within?(name) = name.match?(WITHIN)

        # A Cloud Run job's entries are on cloud_run_job with its job_name and location, and a v2 call's resource name holds
        # both, a v1 call's namespaces/<project>/jobs/<name> only the job.
        def job_resource(project, labels, name)
          job = labels["job_name"].presence || name[%r{/jobs/([^/]+)}, 1]
          location = labels["location"].presence || name[%r{locations/([^/]+)}, 1]
          [ ResourceMap::KIND_JOB, "projects/#{project}/locations/#{location}/jobs/#{job}" ] if job && location
        end

        # A Cloud Deploy call names its pipeline, or a release or rollout inside it, which reads the pipeline and its stages
        # again. A target can be in any pipeline, so a change to one reads the stages in a sweep.
        def deploy_resource(project, name)
          found = name.match(%r{locations/(?<location>[^/]+)/deliveryPipelines/(?<pipeline>[^/:]+)})
          return [ ResourceMap::KIND_PIPELINE, "projects/#{project}/locations/#{found[:location]}/deliveryPipelines/#{found[:pipeline]}" ] if found

          [ ResourceMap::KIND_RELEASE_FLOW, nil ] if name.match?(%r{/targets/})
        end

        # A Cloud SQL instance's entries are on cloudsql_database, whose database_id is project:instance and region its
        # region, which together make the connection name the map keeps. Without the region the kind is read in a sweep.
        def sql_resource(project, labels, name)
          instance = labels["database_id"].to_s.split(":").last.presence || name[%r{instances/([^/]+)}, 1]
          return unless instance

          region = labels["region"].presence
          [ ResourceMap::KIND_DATABASE, (region ? "#{project}:#{region}:#{instance}" : nil) ]
        end

        # A Compute Engine instance's resource name is projects/<project>/zones/<zone>/instances/<name>, its self link path.
        def machine_resource(project, labels, name)
          found = name.match(%r{zones/(?<zone>[^/]+)/instances/(?<name>[^/]+)})
          [ ResourceMap::KIND_VIRTUAL_MACHINE, "projects/#{project}/zones/#{found[:zone]}/instances/#{found[:name]}" ] if found
        end

        # A GKE cluster's entries are on gke_cluster or gke_nodepool with its cluster_name and location. A call through the
        # older zones path names the zone where the map keeps a location.
        def cluster_resource(project, labels, name)
          cluster = labels["cluster_name"].presence || name[%r{clusters/([^/]+)}, 1]
          location = labels["location"].presence || name[%r{(?:locations|zones)/([^/]+)}, 1]
          [ ResourceMap::KIND_CLUSTER, "projects/#{project}/locations/#{location}/clusters/#{cluster}" ] if cluster && location
        end

        def time(value)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          Time.current
        end

        def api(row)
          settings = ConnectionSettings.of(row)
          key = settings.credential(Packs::GoogleCloud::KEY)
          raise Integrations::Error, "This connection has no Google Cloud key. Reconnect it on the Integrations page." if key.blank?

          GoogleCloudApi.new(key, token_cache: settings)
        end
      end
    end
  end
end
