# Platform constants for multi-platform support
# Used to avoid magic strings and provide a single source of truth
module Platforms
  SLACK = "slack"
  TEAMS = "teams"

  # All supported platforms
  ALL = [ SLACK, TEAMS ].freeze

  # Check if a platform is supported
  def self.supported?(platform)
    ALL.include?(platform)
  end

  # Get platform display name
  def self.display_name(platform)
    case platform
    when SLACK
      "Slack"
    when TEAMS
      "Microsoft Teams"
    else
      platform.to_s.capitalize
    end
  end
end
