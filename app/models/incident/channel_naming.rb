# Builds the platform channel name for an incident, shaped inc-2026-08-23-title-slug.
module Incident::ChannelNaming
  extend ActiveSupport::Concern

  def generated_channel_name
    date = (declared_at || Time.current).strftime("%Y-%m-%d")
    slug = (name.presence || "untitled").parameterize[0..50]
    "inc-#{date}-#{slug}"
  end
end
