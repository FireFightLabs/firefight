module Mcp
  module Tools
    # The three settings under Settings, Workspace. Transcript access is here rather than on
    # Permissions on purpose: a grant says who may ask, this says whether there is anything to ask for.
    class UpdateWorkspaceSettings < Base
      SETTINGS = %i[transcript_access_enabled transcript_retention_days archive_channel_delay].freeze
      # The same choices the settings page offers, listed so a model picks one that exists.
      ARCHIVE_CHOICES = "One of: " + Workspace::ChannelArchival::ARCHIVE_DELAY_CHOICES.map { |choice| "#{choice.value} (#{choice.label})" }.join(", ")

      tool_name UPDATE_WORKSPACE_SETTINGS
      authorize_as Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE
      description "Change the workspace's own settings: whether incident transcripts may be read at all, " \
                  "how many days they are kept, and how long after an incident ends its channel is " \
                  "archived. Give only the settings to change. Read the current values with " \
                  "get_workspace_config. Only a workspace admin may call this. Docs: #{Docs::MCP_SERVER}"
      # Workspace wide and made rarely, so a chat asks before any of them.
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          transcript_access_enabled: { type: "boolean", description: "Whether incident channel transcripts may be read by AI and over the API at all" },
          transcript_retention_days: { type: [ "integer", "null" ], description: "Days to keep a transcript after the incident ends. null keeps them forever" },
          archive_channel_delay: { type: "string", description: "How long after an incident ends its channel is archived. #{ARCHIVE_CHOICES}" }
        }
      )

      def self.current(workspace)
        {
          transcript_access_enabled: workspace.transcript_access_enabled,
          transcript_retention_days: workspace.transcript_retention_days,
          archive_channel_delay: workspace.archive_channel_delay
        }
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        changes = args.slice(*SETTINGS)
        return Mcp::ToolDispatcher.error_response("Give at least one setting to change: #{SETTINGS.join(', ')}.") if changes.empty?

        workspace.update!(changes)
        respond(current(workspace).merge(changed: changes.keys.map(&:to_s)))
      rescue ActiveRecord::RecordInvalid => e
        Mcp::ToolDispatcher.error_response(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
