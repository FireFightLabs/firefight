# Shared concern for finding a workspace from a Slack interaction payload
module Interactions
  module WorkspaceFinding
    private

    def find_workspace(payload)
      team_id = payload.dig("team", "id") || payload.dig("user", "team_id")
      Workspace.find_by!(platform: "slack", platform_id: team_id)
    end
  end
end
