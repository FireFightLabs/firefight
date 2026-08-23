class WorkspaceAdapter
  class UnsupportedPlatformError < StandardError; end


  # The one way to reach a platform. Every caller asks for the workspace's
  # adapter here rather than naming Slack or Teams itself.
  #
  #   adapter = WorkspaceAdapter.for(workspace)
  #   result = adapter.create_incidents_channel
  def self.for(workspace)
    case workspace.platform
    when Platforms::SLACK
      Slack::WorkspaceAdapter.new(workspace)
    when Platforms::TEAMS
      Teams::WorkspaceAdapter.new(workspace)
    else
      raise UnsupportedPlatformError, "Unsupported platform: #{workspace.platform}"
    end
  end
end
