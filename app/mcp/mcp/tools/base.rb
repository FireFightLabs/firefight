module Mcp
  module Tools
    # Read-only MCP tools. Workspace-scoped queries and formatting, nothing
    # else. No writes, no adapter calls, no business logic. Dispatch, meaning
    # permissions and telemetry, lives in Mcp::ToolDispatcher, and tools never
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
        # as. Static for most tools. Upserts override the instance method to
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

        # Shared body for approve/deny tools. Structurally human-only. The
        # model's approve!/deny! take a WorkspaceMembership, so service keys
        # (and future Agent principals) cannot resolve approvals at all.
        def resolve_approval(workspace, principal, args, decision)
          unless principal.is_a?(WorkspaceMembership)
            return Mcp::ToolDispatcher.error_response(
              "Only a human can resolve approvals — connect with a personal token or OAuth."
            )
          end

          approval = workspace.ability_approvals.find_by!(id: args[:id].to_s)
          decision == :approve ? approval.approve!(by: principal) : approval.deny!(by: principal)
          ApprovalNotificationService.mark_resolved!(approval)

          respond(SearchApprovals.approval_payload(approval))
        rescue Ability::Approval::NotAllowed => e
          Mcp::ToolDispatcher.error_response("Cannot #{decision}: #{e.message}")
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
