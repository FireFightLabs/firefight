module Slack
  class CommandParser < ::CommandParser
    def self.parse(payload)
      payload = payload.with_indifferent_access
      Command.new(
        platform: Platforms::SLACK,
        workspace_id: find_workspace_id(payload[:team_id]),
        user_id: payload[:user_id],
        text: payload[:text].to_s.strip,
        trigger_id: payload[:trigger_id],
        channel_id: payload[:channel_id],
        metadata: {
          team_id: payload[:team_id],
          team_domain: payload[:team_domain],
          channel_name: payload[:channel_name],
          user_name: payload[:user_name],
          command: payload[:command],
          response_url: payload[:response_url]
        }
      )
    end

    private

    def self.find_workspace_id(team_id)
      workspace = Workspace.find_by(platform: Platforms::SLACK, platform_id: team_id)
      workspace&.id
    end
  end
end
