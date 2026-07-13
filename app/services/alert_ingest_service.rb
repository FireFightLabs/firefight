# Owns the alert pipeline after the controller has verified + normalized:
# persist-first (unique index = idempotency), fingerprint dedup, flap
# handling, grouping, policy routing, incident creation/attachment via
# IncidentLifecycleService, and throttled Slack digest updates.
class AlertIngestService
  FLAP_WINDOW = 5.minutes
  NOTIFY_MIN_INTERVAL = 60.seconds
  DEFAULT_GROUPING_WINDOW_MINUTES = 10
  DEFAULT_CONTENT_MATCH_FIELDS = [ "service" ].freeze

  ACTION_AUTO_CREATE = "auto_create_incident"
  ACTION_ATTACH = "attach_to_incident"
  ACTION_NOTIFY_ONLY = "notify_only"
  ACTION_DROP = "drop"

  def initialize(alert_source)
    @source = alert_source
    @workspace = alert_source.workspace
  end

  def ingest(fields, payload)
    now = Time.current

    if fields["status"] == Alert::STATUS_RESOLVED
      return handle_resolved(fields, now)
    end

    fingerprint = fields["fingerprint"].presence || Alert.fallback_fingerprint(@source.id, fields)

    # Dedup: a firing for an already-open fingerprint is one indexed UPDATE —
    # no new row, no new incident, no new channel.
    if (open_alert = @source.alerts.open_status.find_by(fingerprint: fingerprint))
      open_alert.record_firing!(now)
      notify_digest(open_alert)
      return open_alert
    end

    # Flap: re-fire shortly after resolving reopens the same alert instead of
    # minting a new one.
    if (flapped = recently_resolved(fingerprint, now))
      flapped.record_firing!(now)
      notify_digest(flapped)
      return flapped
    end

    alert = persist(fields, payload, fingerprint, now)
    return alert unless alert.routing_state == Alert::ROUTING_PENDING

    route(alert)
    alert
  end

  # Routing failures leave the alert in routing_state: pending for the sweep
  # job — the alert itself is already safe, so ingestion never surfaces a 500
  # for a routing problem.
  def route(alert)
    result = routing_policy&.evaluate(routing_context(alert))

    unless result&.matched?
      alert.update!(routing_state: Alert::ROUTING_UNMATCHED, routed_at: Time.current)
      return
    end

    apply_outcome(alert, result.outcome)
    alert.update!(routing_state: Alert::ROUTING_ROUTED, routed_at: Time.current)
  rescue StandardError => e
    Rails.logger.error({ event: "alert_routing.failed", alert_id: alert.id, error: e.message }.to_json)
  end

  private

  def handle_resolved(fields, now)
    fingerprint = fields["fingerprint"].presence || Alert.fallback_fingerprint(@source.id, fields)
    alert = @source.alerts.open_status.find_by(fingerprint: fingerprint)
    return nil unless alert

    alert.resolve!(now)
    record_incident_event(alert, IncidentEvent::ALERT_RESOLVED)
    notify_digest(alert, force: true)
    alert
  end

  def recently_resolved(fingerprint, now)
    @source.alerts
      .where(status: Alert::STATUS_RESOLVED, fingerprint: fingerprint)
      .where("resolved_at > ?", now - FLAP_WINDOW)
      .order(resolved_at: :desc)
      .first
  end

  def persist(fields, payload, fingerprint, now)
    external_id = fields["external_id"].presence || Digest::SHA256.hexdigest(payload.to_json)

    @source.alerts.create!(
      workspace: @workspace,
      external_id: external_id,
      fingerprint: fingerprint,
      status: Alert::STATUS_FIRING,
      fields: fields,
      payload: payload,
      received_at: now,
      last_seen_at: now
    )
  rescue ActiveRecord::RecordNotUnique
    # Duplicate provider delivery — the earlier insert already won.
    @source.alerts.find_by!(external_id: external_id)
  end

  def routing_policy
    @routing_policy ||= @workspace.policies.enabled.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
  end

  def routing_context(alert)
    Policy::ContextBuilder.build(
      workspace: @workspace,
      fields: alert.fields.merge("source" => @source.name, "provider" => @source.provider)
    )
  end

  def apply_outcome(alert, outcome)
    case outcome["action"]
    when ACTION_DROP
      nil
    when ACTION_NOTIFY_ONLY
      notify_channel(alert, outcome)
    when ACTION_AUTO_CREATE, ACTION_ATTACH
      incident = grouped_incident(alert)
      incident ||= create_incident(alert, outcome) if outcome["action"] == ACTION_AUTO_CREATE
      attach(alert, incident) if incident
    else
      Rails.logger.warn({ event: "alert_routing.unknown_action", alert_id: alert.id, action: outcome["action"] }.to_json)
    end
  end

  def grouped_incident(alert)
    group = AlertGroup.open_window
      .where(workspace: @workspace, content_signature: content_signature(alert))
      .order(window_expires_at: :desc)
      .first
    return nil unless group
    return nil if group.incident.incident_status.incident_lifecycle_stage.closed?

    alert.alert_group = group
    group.incident
  end

  def create_incident(alert, outcome)
    severity = outcome_severity(outcome) || @source.resolve_severity(alert.fields["severity_raw"])
    raise ArgumentError, "no severity resolvable for alert #{alert.id} (set a workspace default severity)" unless severity

    incident = IncidentLifecycleService.new(@workspace).create(
      declared_by: nil,
      incident_status: @workspace.incident_statuses.default_status,
      incident_severity: severity,
      name: alert.title.truncate(120),
      summary: alert.fields["description"],
      source: Incident::SOURCE_ALERT
    )

    AlertGroup.create!(
      workspace: @workspace,
      incident: incident,
      content_signature: content_signature(alert),
      window_expires_at: Time.current + grouping_window
    )

    incident
  end

  def attach(alert, incident)
    alert.incident = incident
    alert.save!
    record_incident_event(alert, IncidentEvent::ALERT_ATTACHED)
    notify_digest(alert, force: true)
  end

  # notify_only posts the digest to a channel without an incident — an
  # explicit channel id on the outcome, or a catalog-resolved context key
  # (e.g. channel_context_key: "team.channel").
  def notify_channel(alert, outcome)
    channel_id = outcome["channel"].presence || routing_context(alert)[outcome["channel_context_key"].to_s]
    return if channel_id.blank?

    result = WorkspaceAdapter.for(@workspace).post_alert_message(channel_id: channel_id, alert: alert)
    alert.update!(channel_message_id: result[:message_id], last_notified_at: Time.current)
  rescue AdapterError => e
    Rails.logger.warn({ event: "alert_notify.failed", alert_id: alert.id, error: e.message }.to_json)
  end

  def outcome_severity(outcome)
    return nil if outcome["severity_id"].blank?

    @workspace.incident_severities.active.find_by(id: outcome["severity_id"])
  end

  def content_signature(alert)
    AlertGroup.signature_for(alert.fields, content_match_fields)
  end

  def content_match_fields
    routing_policy&.domain_config&.fetch("content_match_fields", nil).presence || DEFAULT_CONTENT_MATCH_FIELDS
  end

  def grouping_window
    minutes = routing_policy&.domain_config&.fetch("grouping_window_minutes", nil).presence || DEFAULT_GROUPING_WINDOW_MINUTES
    minutes.to_i.minutes
  end

  def record_incident_event(alert, event_type)
    return unless alert.incident

    alert.incident.incident_events.create!(
      event_type: event_type,
      metadata: { alert_id: alert.id, title: alert.title, source: @source.name, event_count: alert.event_count }
    )
  end

  # Slack digest throttling: one message per alert that gets updated, never a
  # post per firing. Status transitions (attach/resolve) bypass the interval.
  def notify_digest(alert, force: false)
    channel_id = alert.incident&.channel_id
    return if channel_id.blank?

    adapter = WorkspaceAdapter.for(@workspace)

    if alert.channel_message_id.present?
      return if !force && alert.last_notified_at.present? && alert.last_notified_at > NOTIFY_MIN_INTERVAL.ago

      adapter.update_alert_message(channel_id: channel_id, message_id: alert.channel_message_id, alert: alert)
      alert.update!(last_notified_at: Time.current)
    else
      result = adapter.post_alert_message(channel_id: channel_id, alert: alert)
      alert.update!(channel_message_id: result[:message_id], last_notified_at: Time.current)
    end
  rescue AdapterError => e
    Rails.logger.warn({ event: "alert_digest.failed", alert_id: alert.id, error: e.message }.to_json)
  end
end
