module Mcp
  module Tools
    # Read-only MCP tools: workspace-scoped queries + formatting, nothing
    # else — no writes, no adapter calls, no business logic. Dispatch
    # (permissions, telemetry) lives in Mcp::ToolDispatcher; tools never
    # read Current.
    class Base < ::MCP::Tool
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 50

      READ_ONLY = {
        read_only_hint: true, destructive_hint: false,
        idempotent_hint: true, open_world_hint: false
      }.freeze
      WRITE = {
        read_only_hint: false, destructive_hint: false,
        idempotent_hint: true, open_world_hint: false
      }.freeze
      DESTRUCTIVE = {
        read_only_hint: false, destructive_hint: true,
        idempotent_hint: true, open_world_hint: false
      }.freeze

      class << self
        def call(server_context:, **args)
          Mcp::ToolDispatcher.call(tool: self, server_context: server_context, args: args)
        end

        def perform(workspace:, args:)
          raise NotImplementedError
        end

        # The [resource, crud_action] pair the gateway authorizes this call
        # as. Static for most tools; upserts override the instance method to
        # split create vs update by whether the target exists.
        def authorize_as(resource, action = ApiKey::ACTION_READ)
          @authorization = [ resource, action ]
        end

        def authorization(_workspace, _args)
          @authorization || raise(NotImplementedError, "#{name} declares no authorization")
        end

        private

        def respond(payload)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: JSON.pretty_generate(payload) } ],
            structured_content: payload
          )
        end

        # Fetch limit+1 so truncation is reported explicitly, never silent.
        def capped(scope, args)
          limit = args[:limit].to_i
          limit = DEFAULT_LIMIT unless limit.positive?
          limit = [ limit, MAX_LIMIT ].min
          records = scope.limit(limit + 1).to_a
          [ records.first(limit), records.size > limit ]
        end

        def time_arg(value)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
