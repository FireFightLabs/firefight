class EscalationAcknowledgementTracker
  KEY_PREFIX = "incident"
  ACK_TTL = 7.days

  def self.mark_acknowledged!(workspace_id:, escalation_event_id:)
    Rails.cache.write(cache_key(workspace_id, escalation_event_id), true, expires_in: ACK_TTL)
  end

  def self.acknowledged?(workspace_id:, escalation_event_id:)
    !!Rails.cache.read(cache_key(workspace_id, escalation_event_id))
  end

  def self.cache_key(workspace_id, escalation_event_id)
    "#{KEY_PREFIX}:#{workspace_id}:escalation_ack:#{escalation_event_id}"
  end
  private_class_method :cache_key
end
