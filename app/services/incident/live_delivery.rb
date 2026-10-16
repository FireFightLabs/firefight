# Tells open incident pages which part of them changed (Incident::LiveSignal), over IncidentChannel. An alert storm or a
# busy run can change one part many times a second, so each incident and part is said at most once per WINDOW. A change
# inside the window is never lost: the first one held back books a single trailing say (IncidentPageSignalJob) for after
# the window, which covers every change made before it runs and books another if the gate is still held.
class Incident::LiveDelivery
  WINDOW = 1.second

  def self.changed(incident_id:, part:)
    return say(incident_id, part) if Rails.cache.write(gate_key(incident_id, part), true, unless_exist: true, expires_in: WINDOW)
    return unless Rails.cache.write(trailing_key(incident_id, part), true, unless_exist: true, expires_in: WINDOW)

    IncidentPageSignalJob.set(wait: WINDOW).perform_later(incident_id, part)
  end

  # The trailing say goes through the gate too, so a change said directly just before it does not make two in one window.
  # Its own booking is cleared first, so if the gate holds it back it books the next one rather than being lost.
  def self.trailing(incident_id:, part:)
    Rails.cache.delete(trailing_key(incident_id, part))
    changed(incident_id: incident_id, part: part)
  end

  def self.say(incident_id, part)
    ActionCable.server.broadcast(IncidentChannel.stream_name(incident_id), { part: part })
  end

  def self.gate_key(incident_id, part) = "incident_page/#{incident_id}/#{part}"

  def self.trailing_key(incident_id, part) = "incident_page/#{incident_id}/#{part}/trailing"
end
