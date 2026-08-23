# Every reference to a platform goes through these constants, never a raw string.
module Platforms
  SLACK = "slack"
  TEAMS = "teams"

  ALL = [ SLACK, TEAMS ].freeze

  def self.supported?(platform)
    ALL.include?(platform)
  end

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
