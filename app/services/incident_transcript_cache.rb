class IncidentTranscriptCache
  KEY_PREFIX = "incident"
  MAX_ENTRIES = 2000
  CLOSED_TTL = 1.week

  def self.append(incident:, entry:)
    payload = read_payload(incident)
    entries = payload["entries"] || []
    entries << entry
    entries = entries.last(MAX_ENTRIES)

    write_payload(incident, { "entries" => entries })
  end

  def self.entries(incident)
    (read_payload(incident)["entries"] || []).sort_by { |item| item["ts"].to_f }
  end

  def self.expire_after_close!(incident)
    payload = read_payload(incident)
    return if payload.empty?

    write_payload(incident, payload, expires_in: CLOSED_TTL)
  end

  def self.clear_expiry!(incident)
    payload = read_payload(incident)
    return if payload.empty?

    write_payload(incident, payload)
  end

  def self.clear!(incident)
    Rails.cache.delete(cache_key(incident))
  end

  def self.read_payload(incident)
    Rails.cache.read(cache_key(incident)) || {}
  end
  private_class_method :read_payload

  def self.write_payload(incident, payload, expires_in: nil)
    options = {}
    options[:expires_in] = expires_in if expires_in
    Rails.cache.write(cache_key(incident), payload, **options)
  end
  private_class_method :write_payload

  def self.cache_key(incident)
    "#{KEY_PREFIX}:#{incident.workspace_id}:#{incident.id}:transcript"
  end
  private_class_method :cache_key
end
