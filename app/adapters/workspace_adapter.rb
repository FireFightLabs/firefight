class WorkspaceAdapter
  class UnsupportedPlatformError < StandardError; end


  def self.refresh_expiring_credentials(buffer:)
    Slack::WorkspaceAdapter.refresh_expiring_credentials(buffer: buffer)
  end

  # The one way to reach a platform. Callers never name Slack or Teams.
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
