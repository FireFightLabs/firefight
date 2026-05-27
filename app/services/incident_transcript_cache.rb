class IncidentTranscriptCache
  KEY_PREFIX = "incident"
  MAX_ENTRIES = 2000
  # Active incidents auto-renew via every new message, so the cache stays warm
  # as long as people are talking. Stale-open incidents fall out naturally.
  ACTIVE_TTL = 60.days
  # Sized to cover the typical reopen window (days to a few weeks) without
  # requiring a Slack history rebuild. Longer reopens lose the cache and
  # currently degrade to partial catchup; rebuild-on-miss is tracked
  # separately as a follow-up.
  CLOSED_TTL = 30.days

  def self.append(incident:, entry:)
    payload = read_payload(incident)
    entries = payload["entries"] || []
    entries << entry
    entries = entries.last(MAX_ENTRIES)

    write_payload(incident, { "entries" => entries }, expires_in: ACTIVE_TTL)
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

    write_payload(incident, payload, expires_in: ACTIVE_TTL)
  end

  def self.grouped_messages(incident, workspace:)
    raw = entries(incident)
    return [] if raw.blank?

    members = workspace.workspace_memberships.index_by(&:platform_user_id)

    top_level = []
    threads = Hash.new { |h, k| h[k] = [] }

    raw.each do |entry|
      resolved_name = members[entry["user_id"]]&.user&.name || entry["user_id"]
      formatted = {
        at: entry["created_at"],
        by: resolved_name,
        text: entry["text"],
        ts: entry["ts"]
      }

      if entry["is_thread_reply"]
        threads[entry["parent_ts"]] << formatted
      else
        top_level << formatted
      end
    end

    top_level.map do |msg|
      replies = threads[msg[:ts]]
      replies.any? ? msg.merge(replies: replies) : msg
    end
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
