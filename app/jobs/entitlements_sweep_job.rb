# Lets a hosted build's entitlements backend run its daily upkeep. An install someone runs themselves has none.
class EntitlementsSweepJob < ApplicationJob
  queue_as :background

  def perform
    Entitlements.sweep!
  end
end
