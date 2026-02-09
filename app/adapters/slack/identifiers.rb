# Centralized Slack callback_ids, action_ids, and shortcut identifiers
# Referenced by modal/message builders, the interaction dispatcher, and tests
module Slack
  module Identifiers
    # Modal callback_ids (view_submission)
    INCIDENT_CREATION_MODAL = "incident_creation_modal"
    SHARE_INCIDENTS_CHANNEL_MODAL = "share_incidents_channel_modal"

    # Shortcut callback_ids
    CREATE_INCIDENT_SHORTCUT = "create_incident_shortcut"

    # Block action_ids (block_actions)
    SHARE_INCIDENTS_CHANNEL = "share_incidents_channel"
    PREVIEW_ANNOUNCEMENT = "preview_announcement"
    PREVIEW_HOMEPAGE_DISABLED = "preview_homepage_disabled"
    PREVIEW_SUBSCRIBE_DISABLED = "preview_subscribe_disabled"
  end
end
