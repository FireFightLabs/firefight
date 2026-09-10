# Retries alerts whose inline routing failed and left the row pending.
class Alerts::RoutingSweepJob < ApplicationJob
  queue_as :events

  STALE_AFTER = 2.minutes

  def perform
    Alert.pending_routing
      .where("received_at < ?", STALE_AFTER.ago)
      .includes(:alert_source)
      .find_each do |alert|
        AlertIngestService.new(alert.alert_source).route(alert)
      end
  end
end
