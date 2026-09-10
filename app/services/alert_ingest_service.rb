# At most one open alert per source and fingerprint, insert losers fold into record_firing!.
# Routing is a row lock CAS on routing_state so duplicate deliveries and sweeps never double-apply.
# Grouping takes a per-signature advisory lock so a storm creates one incident.
# Slack calls run after the routing transaction commits.
class AlertIngestService
  NOTIFY_MIN_INTERVAL = 60.seconds

  ACTION_AUTO_CREATE = PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE
  ACTION_ATTACH = PolicyRule::AlertRoutingOutcome::ACTION_ATTACH
  ACTION_NOTIFY_ONLY = PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY
  ACTION_DROP = PolicyRule::AlertRoutingOutcome::ACTION_DROP

  def initialize(alert_source)
    @source = alert_source
    @workspace = alert_source.workspace
  end

  def ingest(fields, payload)
    now = Time.current
    fingerprint = fields["fingerprint"].presence || Alert.fallback_fingerprint(@source, fields)

    if fields["status"] == Alert::STATUS_RESOLVED
      return handle_resolved(fingerprint, now)
    end

    # A firing for an open fingerprint is one indexed update, no new row or incident.
    if (open_alert = @source.alerts.open_status.find_by(fingerprint: fingerprint))
      open_alert.record_firing!(now)
      notify_digest(open_alert)
      return open_alert
    end

    # A re-fire shortly after resolving reopens the same alert instead of minting a new one.
    if (flapped = recently_resolved(fingerprint, now))
      reopen(flapped, now)
      return flapped
    end

    alert, created = persist(fields, payload, fingerprint, now)
    # Only the insert winner routes inline. Losers leave it to the winner or the sweep.
    route(alert) if created && alert.routing_state == Alert::ROUTING_PENDING
    alert
  end

  # A routing failure leaves the alert pending for the sweep (failed after
  # MAX_ROUTING_ATTEMPTS), so ingestion never returns a 500 for a routing problem.
  def route(alert)
    deferred_notification = nil

    begin
      alert.with_lock do
        # A duplicate delivery or an overlapping sweep may already have routed it.
        next unless alert.routing_state == Alert::ROUTING_PENDING

        result = router.route(alert.fields)

        if result&.matched?
          deferred_notification = apply_outcome(alert, result.outcome)
          alert.mark_routed!(result.matched_rule)
        else
          alert.mark_unmatched!
        end
      end
    rescue StandardError => e
      Rails.logger.error({ event: "alert_routing.failed", alert_id: alert.id, error: e.message }.to_json)
      alert.record_routing_failure!
      return
    end

    # Committed by now. A failure here is a notification problem, so the alert
    # stays routed instead of going back to pending and being applied twice by the sweep.
    deferred_notification&.call
  rescue StandardError => e
    Rails.logger.error({ event: "alert_notification.failed", alert_id: alert.id, error: e.message }.to_json)
  end

  private

  def handle_resolved(fingerprint, now)
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
      .where("resolved_at > ?", now - @source.flap_window)
      .order(resolved_at: :desc)
      .first
  end

  # A flap onto a closed incident is a fresh episode. Detach and re-route so the
  # regression is visible instead of editing a digest in a closed channel.
  def reopen(alert, now)
    alert.record_firing!(now)

    if alert.incident&.terminal?
      alert.reset_routing!
      route(alert)
    else
      notify_digest(alert)
    end
  end

  def persist(fields, payload, fingerprint, now)
    external_id = fields["external_id"].presence || fallback_external_id(fields, payload)
    alert = @source.alerts.create!(
      workspace: @workspace,
      external_id: external_id,
      fingerprint: fingerprint,
      status: Alert::STATUS_FIRING,
      fields: fields,
      payload: payload,
      received_at: now,
      last_seen_at: now
    )
    [ alert, true ]
  rescue ActiveRecord::RecordNotUnique
    # Same external_id, a byte-identical redelivery already counted.
    if (duplicate = @source.alerts.find_by(external_id: external_id))
      [ duplicate, false ]
    else
      # Lost the open-fingerprint insert race, count this firing on the winner's row.
      winner = @source.alerts.open_status.find_by!(fingerprint: fingerprint)
      winner.record_firing!(now)
      notify_digest(winner)
      [ winner, false ]
    end
  end

  # Unique per item within a batched delivery (Alertmanager posts arrays) yet
  # stable across redeliveries, so hash the normalized fields with the item payload.
  def fallback_external_id(fields, payload)
    Digest::SHA256.hexdigest("#{payload.to_json}\n#{fields.to_json}")
  end

  def router
    @router ||= Alert::Router.new(@workspace, @source)
  end

  def routing_policy
    router.policy
  end

  # DB writes only, inside the routing transaction. Anything that talks to Slack
  # comes back as a deferred callable and runs after commit.
  def apply_outcome(alert, outcome)
    case outcome["action"]
    when ACTION_DROP
      nil
    when ACTION_NOTIFY_ONLY
      -> { notify_channel(alert, outcome) }
    when ACTION_AUTO_CREATE, ACTION_ATTACH
      lock_signature!(alert)
      incident = grouped_incident(alert)
      notes = nil
      if incident.nil? && outcome["action"] == ACTION_AUTO_CREATE
        resolver = target_resolver(alert)
        incident = create_incident(alert, outcome, resolver)
        notes = resolver.notes
      end
      if incident
        attach(alert, incident, unresolved_targets: notes)
        -> { notify_digest(alert, force: true) }
      end
    else
      Rails.logger.warn({ event: "alert_routing.unknown_action", alert_id: alert.id, action: outcome["action"] }.to_json)
      nil
    end
  end

  # Transaction-scoped advisory lock so concurrent same-signature alerts
  # serialize through group lookup and incident creation.
  def lock_signature!(alert)
    key = Zlib.crc32("alert_grouping:#{@workspace.id}:#{content_signature(alert)}")
    sql = ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ])
    ActiveRecord::Base.connection.select_value(sql)
  end

  def grouped_incident(alert)
    group = AlertGroup.open_window
      .where(workspace: @workspace, content_signature: content_signature(alert))
      .order(window_expires_at: :desc)
      .first
    return nil unless group
    return nil if group.incident.terminal?

    alert.alert_group = group
    group.incident
  end

  def create_incident(alert, outcome, resolver)
    severity = outcome_severity(outcome) || @source.resolve_severity(alert.fields["severity_raw"])
    raise ArgumentError, "no severity resolvable for alert #{alert.id} (set a workspace default severity)" unless severity

    invitee_ids = resolver.memberships_for(outcome["invite"]).map(&:id)

    incident = IncidentLifecycleService.new(@workspace).create(
      declared_by: nil,
      incident_status: @workspace.incident_statuses.default_status,
      incident_severity: severity,
      name: alert.title.truncate(120),
      summary: alert.fields["description"],
      source: Incident::SOURCE_ALERT,
      workflow_context: invitee_ids.any? ? { invite_membership_ids: invitee_ids } : {}
    )

    AlertGroup.create!(
      workspace: @workspace,
      incident: incident,
      content_signature: content_signature(alert),
      window_expires_at: Time.current + grouping_window
    )

    incident
  end

  def attach(alert, incident, unresolved_targets: nil)
    alert.incident = incident
    alert.save!
    record_incident_event(alert, IncidentEvent::ALERT_ATTACHED, unresolved_targets: unresolved_targets)
  end

  # Skips when a digest already exists so a sweep retry after a partial failure cannot double-post.
  def notify_channel(alert, outcome)
    return if alert.channel_message_id.present?

    target = target_resolver(alert).channel_for(outcome["notify"])
    return if target.blank?

    result = WorkspaceAdapter.for(@workspace).post_alert_message(channel_id: target, alert: alert)
    alert.update!(
      channel_id: result[:channel_id] || target,
      channel_message_id: result[:message_id],
      last_notified_at: Time.current
    )
  rescue AdapterError => e
    Rails.logger.warn({ event: "alert_notify.failed", alert_id: alert.id, error: e.message }.to_json)
  end

  def target_resolver(alert)
    Alert::TargetResolver.new(@workspace, alert.fields)
  end

  def outcome_severity(outcome)
    return nil if outcome["severity_id"].blank?

    @workspace.incident_severities.active.find_by(id: outcome["severity_id"])
  end

  def content_signature(alert)
    AlertGroup.signature_for(alert.fields, content_match_fields)
  end

  def content_match_fields
    routing_policy&.content_match_fields || Policy::AlertRoutingConfig::DEFAULT_CONTENT_MATCH_FIELDS
  end

  def grouping_window
    (routing_policy&.grouping_window_minutes || Policy::AlertRoutingConfig::DEFAULT_WINDOW_MINUTES).minutes
  end

  def record_incident_event(alert, event_type, unresolved_targets: nil)
    return unless alert.incident

    metadata = { alert_id: alert.id, title: alert.title, source: @source.name, event_count: alert.event_count }
    metadata[:unresolved_targets] = unresolved_targets if unresolved_targets.present?

    alert.incident.incident_events.create!(event_type: event_type, metadata: metadata)
  end

  # Status transitions bypass the interval. The send is claimed with a conditional UPDATE on
  # last_notified_at so concurrent firings race on an indexed write instead of holding a row lock
  # through the Slack call. The claim sticks when the send fails, so a storm into a broken channel does not retry on every delivery.
  def notify_digest(alert, force: false)
    channel_id = alert.incident&.channel_id || alert.channel_id
    return if channel_id.blank?

    claim = Alert.where(id: alert.id)
    claim = claim.where("last_notified_at IS NULL OR last_notified_at <= ?", NOTIFY_MIN_INTERVAL.ago) unless force
    return if claim.update_all(last_notified_at: Time.current, updated_at: Time.current).zero?

    alert.reload
    adapter = WorkspaceAdapter.for(@workspace)
    if alert.channel_message_id.present?
      adapter.update_alert_message(channel_id: channel_id, message_id: alert.channel_message_id, alert: alert)
    else
      result = adapter.post_alert_message(channel_id: channel_id, alert: alert)
      alert.update!(channel_id: channel_id, channel_message_id: result[:message_id])
    end
  rescue AdapterError => e
    Rails.logger.warn({ event: "alert_digest.failed", alert_id: alert.id, error: e.message }.to_json)
  end
end
