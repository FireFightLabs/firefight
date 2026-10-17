# Sends the trailing signal for changes Incident::LiveDelivery held back inside its window.
class IncidentPageSignalJob < ApplicationJob
  queue_as :events

  def perform(incident_id, part)
    Incident::LiveDelivery.trailing(incident_id: incident_id, part: part)
  end
end
