# frozen_string_literal: true

# Incident::ChannelNaming - Platform channel name generation
#
# Generates Slack/Teams channel names for incidents.
# Format: inc-001-title-slug
#
module Incident::ChannelNaming
  extend ActiveSupport::Concern

  # Generate Slack/Teams channel name
  def generated_channel_name
    date = (declared_at || Time.current).strftime("%Y-%m-%d")
    slug = (name.presence || "untitled").parameterize[0..50]
    "inc-#{date}-#{slug}"
  end
end
