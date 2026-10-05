module Integrations
  module Capabilities
    # DigitalOcean's own tools answer each capability, by the resource's DigitalOcean id: App Platform apps
    # (apps_get_logs, apps_list_deployments, apps_get, apps_create_rollback, apps_restart, apps_update), Droplets
    # (droplets_get) and managed databases (databases_get_cluster), with metrics from
    # /v2/monitoring/metrics, as DigitalOcean's OpenAPI specification gives them (digitalocean/openapi).
    module Digitalocean
      extend Adapter

      APP = ResourceMap::KIND_SERVICE
      DROPLET = ResourceMap::KIND_VIRTUAL_MACHINE
      DATABASE = ResourceMap::KIND_DATABASE
      SUPPORTS = {
        LOGS => [ APP ], METRICS => [ APP, DROPLET, DATABASE ], DEPLOYS => [ APP ], STATUS => [ APP, DROPLET, DATABASE ],
        ROLLBACK => [ APP ], RESTART => [ APP, DROPLET ], SCALE => [ APP ]
      }.freeze
      TOOLS = {
        LOGS => "app_logs", METRICS => "resource_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_app", RESTART => %w[restart_app reboot_droplet], SCALE => "scale_app"
      }.freeze
      REBOOT = "reboot_droplet".freeze
      # The tools a capability answers in full. app_logs (deploy logs and crashed instances), resource_metrics (restarts),
      # restart_app and scale_app (one component of an app) take more than their capability does, so they stay offered.
      WRAPPED = [ *TOOLS.values_at(DEPLOYS, STATUS, ROLLBACK), REBOOT ].freeze
      # The log types App Platform keeps that mean the same as a capability's stream.
      STREAMS = { STREAM_APP => "RUN", "build" => "BUILD" }.freeze
      # Metric names DigitalOcean documents an equivalent of. restarts has none among the capability's names, so it is
      # asked of resource_metrics.
      METRIC_MAP = { "cpu" => "cpu", "memory" => "memory", "disk" => "disk", "network_in" => "network_in", "network_out" => "network_out" }.freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS
          stream = given["stream"].presence || STREAM_APP
          unless STREAMS.key?(stream)
            raise Unroutable, "App Platform keeps what an app prints (app) and its builds (build), so stream must be one of those. " \
                              "Its deploy logs and the logs of crashed instances are read with app_logs."
          end
          Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => STREAMS.fetch(stream) }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, METRIC_MAP, "DigitalOcean")
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deployment" => target(given) })
        # A Droplet restarts by rebooting, gracefully, through droplet_actions_post with type reboot.
        when RESTART then Route.new(tool_name: resource.kind == DROPLET ? REBOOT : tool_for(RESTART), arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => scaled(given) })
        end
      end

      # App Platform runs at least one instance of a component, so 0 is refused here rather than by DigitalOcean.
      def self.scaled(given)
        count = instances(given)
        raise Unroutable, "App Platform runs at least one instance of a component, so instances must be 1 or more." if count < 1

        count
      end
      private_class_method :scaled
    end
  end
end
