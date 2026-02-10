class WorkspaceAdapter
  class UnsupportedPlatformError < StandardError; end


  # Factory method to create appropriate adapter based on workspace platform
  #
  # @param workspace [Workspace] The workspace record
  # @return [Slack::WorkspaceAdapter, Teams::WorkspaceAdapter] Platform-specific adapter
  # @raise [UnsupportedPlatformError] if platform is not supported
  #
  # @example
  #   adapter = WorkspaceAdapter.for(workspace)
  #   result = adapter.create_incidents_channel
  #
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
