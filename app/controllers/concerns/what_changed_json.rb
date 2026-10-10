# What changed (ResourceMap::Timeline) as the dashboard reads it, the same for a resource on the map and an incident.
# Runs are read from the provider only when the person asks, as them, through the gateway as run history.
module WhatChangedJson
  extend ActiveSupport::Concern

  private

  def render_what_changed(timeline)
    live_read = params[:live].present?
    live, read = live_read ? ResourceMap::WhatChanged.read_as(timeline, principal: current_membership) : [ [], [] ]
    render json: { entries: ResourceMapTimelineEntrySerializer.many(timeline.entries(live: live)), notes: timeline.notes(read: read),
                   readsRuns: ResourceMap::WhatChanged.targets(timeline).any?, readLive: live_read, from: timeline.from.utc.iso8601 }
  end
end
