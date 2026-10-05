module Integrations
  module Capabilities
    # A Modal app on the map is answered by the Modal pack's own tools, by the app's id. Each tool makes the calls the
    # matching command of Modal's open source client makes (py/modal/cli/app.py): logs, history, info, rollback and
    # rollover. Modal autoscales each function of an app on its own, so an app has no one number of instances to set,
    # and scaling a function is the pack's update_autoscaler. Modal's client offers no metrics, so none are answered.
    module Modal
      extend Adapter

      APP = [ ResourceMap::KIND_SERVICE ].freeze
      SUPPORTS = { LOGS => APP, DEPLOYS => APP, STATUS => APP, ROLLBACK => APP, RESTART => APP }.freeze
      TOOLS = {
        LOGS => "app_logs", DEPLOYS => "deployment_history", STATUS => "describe_app", ROLLBACK => "rollback_app", RESTART => "rollover_app"
      }.freeze
      # app_logs also filters by function and by source, which the capability cannot ask, so it stays offered as it is.
      WRAPPED = TOOLS.values.excluding(TOOLS[LOGS]).freeze
      PASSED = %w[text exclude limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        app = { "app" => resource.external_id }
        case key
        when LOGS
          raise Unroutable, "Modal searches logs by text, not by a regular expression. Give text instead." if given["regex"].present?
          if given["stream"].present? && given["stream"] != STREAM_APP
            raise Unroutable, "Modal keeps what an app's containers print and what Modal says about them, so stream must be #{STREAM_APP}."
          end

          Route.new(tool_name: TOOLS[LOGS], arguments: app.merge(given.slice(*PASSED)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: app.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: app)
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: app.merge("version" => target(given)))
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: app)
        end
      end
    end
  end
end
