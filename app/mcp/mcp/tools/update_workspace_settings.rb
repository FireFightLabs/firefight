module Mcp
  module Tools
    # The settings under Settings, Workspace. Transcript access is here rather than on
    # Permissions on purpose: a grant says who may ask, this says whether there is anything to ask for.
    class UpdateWorkspaceSettings < Base
      SETTINGS = Workspace::Settings::KEYS
      # The same choices the settings page offers, as an enum a client can check and with the labels a model reads.
      ARCHIVE_VALUES = Workspace::ChannelArchival::ARCHIVE_DELAY_CHOICES.map(&:value).freeze
      ARCHIVE_CHOICES = "One of: " + Workspace::ChannelArchival::ARCHIVE_DELAY_CHOICES.map { |choice| "#{choice.value} (#{choice.label})" }.join(", ")
      ISSUE_CREATION_CHOICES = "One of: " + Workspace::IssueSync::ISSUE_CREATION_CHOICES.map { |choice| "#{choice.value} (#{choice.label})" }.join(", ")
      # Each tracker's own fields for where new issues go, as its provider declares them.
      ISSUE_TARGETS = IntegrationProvider.all.filter_map do |entry|
        fields = Integrations::Issues.target_fields(entry.key)
        "#{entry.name}: #{fields.map { |field| "#{field.key} (#{field.hint.delete_suffix('.')})" }.join(', ')}" if fields.any?
      end.join(". ")

      tool_name UPDATE_WORKSPACE_SETTINGS
      authorize_as Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE
      description "Change the workspace's own settings: whether incident transcripts may be read at all, " \
                  "how many days they are kept, how long after an incident ends its channel is " \
                  "archived, whether Halon may search and read the public web, whether Firefight may test Halon on answers the team rated, " \
                  "which connected coding agent writes a fix's code changes, and which issue tracker incident items are kept in step " \
                  "with and when a new item gets an issue there. Give only the settings to change. Read the current values with " \
                  "get_workspace_config. Only a workspace admin may call this. Docs: #{Docs::MCP_SERVER}"
      # Workspace wide and made rarely, so a chat asks before any of them.
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          transcript_access_enabled: { type: "boolean", description: "Whether incident channel transcripts may be read by AI and over the API at all" },
          transcript_retention_days: { type: [ "integer", "null" ], description: "Days to keep a transcript after the incident ends. null keeps them forever" },
          archive_channel_delay: { type: "string", enum: ARCHIVE_VALUES, description: "How long after an incident ends its channel is archived. #{ARCHIVE_CHOICES}" },
          web_search_enabled: { type: "boolean", description: "Whether Halon and its coding agent may search and read the public web, through Firefight" },
          halon_regression_enabled: { type: "boolean", description: "Whether Firefight may replay Halon's investigations whose answer the team confirmed or marked wrong, to test new versions of Halon. Off by default" },
          code_fix_agent: { type: [ "string", "null" ], description: "The connection slug of a connected coding agent (the coding_agents category of list_integrations), the prefix of its tools such as devin in devin_fix_code, which then writes a fix's code changes and opens the pull request. null for Firefight's own agent, the default" },
          issue_tracker: { type: [ "string", "null" ], description: "The connection slug of a connected issue tracker whose issues incident items are kept in step with: title, status and assignee, both ways. null for none" },
          issue_creation: { type: "string", enum: Workspace::IssueSync::ISSUE_CREATIONS, description: "When a new item gets an issue in that tracker. #{ISSUE_CREATION_CHOICES}" },
          issue_tracker_target: { type: "object", additionalProperties: { type: "string" }, description: "Where new issues go, by the chosen tracker's own fields. Replaces what was saved. #{ISSUE_TARGETS}" },
          issue_webhook_secret: { type: "string", description: "The signing secret of the tracker's webhook that sends its changes to Firefight, as the tracker shows it. Never read back" }
        }
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        changes = args.slice(*SETTINGS)
        return Mcp::ToolDispatcher.error_response("Give at least one setting to change: #{SETTINGS.join(', ')}.") if changes.empty?

        workspace.update_settings!(changes)
        respond(workspace.settings.merge(changed: changes.keys.map(&:to_s)))
      rescue ActiveRecord::RecordInvalid => e
        Mcp::ToolDispatcher.error_response(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
