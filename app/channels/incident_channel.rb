# An open incident page, told which part of it changed (Incident::LiveDelivery) so it reads that part again. The signal
# carries no incident data, the page reads it through the same authorized request as always.
class IncidentChannel < ApplicationCable::Channel
  def self.stream_name(incident_id) = "incident:#{incident_id}"

  def subscribed
    incident = Incident.find_by(id: params[:id])
    return reject unless incident&.watchable_by?(current_user)

    stream_from self.class.stream_name(incident.id)
  end
end
