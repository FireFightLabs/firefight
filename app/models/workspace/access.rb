# Whether the workspace may be used at all, asked at every way in: the dashboard, the API, MCP, alerts and the chat
# platform. A suspension is Firefight's own call, the rest is the entitlements backend's.
module Workspace::Access
  extend ActiveSupport::Concern

  # Nil while the workspace may be used. Otherwise an Entitlements::Result saying why, and on a build that has one,
  # the page that puts it right.
  def access_blocked
    return Entitlements.deny(suspension_message) if suspended?

    result = Entitlements.check(self, Entitlements::ACCESS)
    result.blocked? ? result : nil
  end
end
