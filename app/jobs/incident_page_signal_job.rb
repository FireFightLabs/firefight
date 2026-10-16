# The trailing say for changes Incident::LiveDelivery held back inside its window.
class IncidentPageSignalJob < ApplicationJob
  queue_as :events

  def perform(incident_id, part)
    Incident::LiveDelivery.say(incident_id, part)
  end
end
