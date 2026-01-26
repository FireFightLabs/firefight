# frozen_string_literal: true

# Incident::ChannelNaming - Platform channel name generation
#
# Generates Slack/Teams channel names for incidents.
# Format: inc-001-title-slug
#
module Incident::ChannelNaming
  extend ActiveSupport::Concern

  # Generate Slack/Teams channel name
  def channel_name
    slug = (name.presence || "untitled").parameterize[0..50]
    "inc-#{sequence_number.to_s.rjust(3, '0')}-#{slug}"
  end
end
