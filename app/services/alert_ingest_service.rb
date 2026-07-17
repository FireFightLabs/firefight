# Owns the alert pipeline after the controller has verified + normalized:
# persist-first (unique indexes = idempotency), fingerprint dedup, flap
# handling, grouping, policy routing, incident creation/attachment via
# IncidentLifecycleService, and throttled Slack digest updates.
#
# Concurrency invariants:
# - At most one open alert per (source, fingerprint): partial unique index;
#   losers of the insert race fold into the record_firing! path.
# - Routing runs under a row-lock CAS on routing_state, so a duplicate
#   delivery, an overlapping sweep, and the inline path never double-apply.
# - Grouping takes a per-signature advisory lock inside that transaction, so
#   a storm of distinct alerts creates exactly one incident.
# - Slack calls happen after the routing transaction commits.
class AlertIngestService
  NOTIFY_MIN_INTERVAL = 60.seconds
  MAX_ROUTING_ATTEMPTS = 10

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

    if fields["status"] == Alert::STATUS_RESOLVED
      return handle_resolved(fields, now)
    end

    fingerprint = fields["fingerprint"].presence || Alert.fallback_fingerprint(@source, fields)

    # Dedup: a firing for an already-open fingerprint is one indexed UPDATE;
    # no new row, no new incident, no new channel.
    if (open_alert = @source.alerts.open_status.find_by(fingerprint: fingerprint))
      open_alert.record_firing!(now)
      notify_digest(open_alert)
      return open_alert
    end

    # Flap: re-fire shortly after resolving reopens the same alert instead of
    # minting a new one.
    if (flapped = recently_resolved(fingerprint, now))
      reopen(flapped, now)
      return flapped
    end

    alert, created = persist(fields, payload, fingerprint, now)
    # Only the request that won the insert routes inline; losers leave it to
    # the winner (or the sweep, whose CAS makes retries safe).
    route(alert) if created && alert.routing_state == Alert::ROUTING_PENDING
    alert
  end

  # Routing failures leave the alert pending for the sweep job (until
  # MAX_ROUTING_ATTEMPTS, then failed); the alert row itself is already safe,
  # so ingestion never surfaces a 500 for a routing problem.
  def route(alert)
    deferred_notification = nil

    alert.with_lock do
      # CAS: a duplicate delivery or an overlapping sweep already routed it.
      next unless alert.routing_state == Alert::ROUTING_PENDING

      result = routing_policy&.evaluate(routing_context(alert))

      if result&.matched?
        deferred_notification = apply_outcome(alert, result.outcome)
        alert.update!(routing_state: Alert::ROUTING_ROUTED, routed_at: Time.current,
                      matched_policy_rule: result.matched_rule)
      else
        alert.update!(routing_state: Alert::ROUTING_UNMATCHED, routed_at: Time.current)
      end
    end

    deferred_notification&.call
  rescue StandardError => e
    record_routing_failure(alert, e)
  end

  private

  def handle_resolved(fields, now)
    fingerprint = fields["fingerprint"].presence || Alert.fallback_fingerprint(@source, fields)
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

  # A flap onto a closed incident is a fresh episode: detach and re-route so
  # the regression is visible somewhere, instead of editing a digest in a
  # closed (possibly archived) channel.
  def reopen(alert, now)
    alert.record_firing!(now)

    if alert.incident&.closed?
      alert.update!(incident: nil, alert_group: nil, matched_policy_rule: nil,
                    channel_id: nil, channel_message_id: nil, last_notified_at: nil,
                    routing_state: Alert::ROUTING_PENDING, routing_attempts: 0)
      route(alert)
    else
      notify_digest(alert)
    end
  end

  def persist(fields, payload, fingerprint, now)
    alert = @source.alerts.create!(
      workspace: @workspace,
      external_id: fields["external_id"].presence || fallback_external_id(fields, payload),
      fingerprint: fingerprint,
      status: Alert::STATUS_FIRING,
      fields: fields,
      payload: payload,
      received_at: now,
      last_seen_at: now
    )
    [ alert, true ]
  rescue ActiveRecord::RecordNotUnique
    # Same external_id: byte-identical redelivery, already counted.
    if (duplicate = @source.alerts.find_by(external_id: fields["external_id"].presence || fallback_external_id(fields, payload)))
      [ duplicate, false ]
    else
      # Lost the open-fingerprint insert race: the winner's row is
      # authoritative; count this firing there.
      winner = @source.alerts.open_status.find_by!(fingerprint: fingerprint)
      winner.record_firing!(now)
      notify_digest(winner)
      [ winner, false ]
    end
  end

  # Must be unique per item within a batched delivery (Alertmanager posts
  # arrays), yet stable across redeliveries of the same body, so hash the
  # normalized fields together with the item payload.
  def fallback_external_id(fields, payload)
    Digest::SHA256.hexdigest("#{payload.to_json}\n#{fields.to_json}")
  end

  def routing_policy
    return @routing_policy if defined?(@routing_policy)

    @routing_policy = @source.effective_alert_routing_policy
  end

  def routing_context(alert)
    Policy::ContextBuilder.build(
      workspace: @workspace,
      fields: alert.fields.merge("source" => @source.name, "provider" => @source.provider)
    )
  end

  # DB writes happen here, inside the routing transaction; anything that
  # talks to Slack is returned as a deferred callable and runs after commit.
  def apply_outcome(alert, outcome)
    case outcome["action"]
    when ACTION_DROP
      nil
    when ACTION_NOTIFY_ONLY
      -> { notify_channel(alert, outcome) }
    when ACTION_AUTO_CREATE, ACTION_ATTACH
      lock_signature!(alert)
      incident = grouped_incident(alert)
      incident ||= create_incident(alert, outcome) if outcome["action"] == ACTION_AUTO_CREATE
      if incident
        attach(alert, incident)
        -> { notify_digest(alert, force: true) }
      end
    else
      Rails.logger.warn({ event: "alert_routing.unknown_action", alert_id: alert.id, action: outcome["action"] }.to_json)
      nil
    end
  end

  # Transaction-scoped advisory lock so concurrent same-signature alerts
  # serialize through the group lookup + incident creation.
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
    return nil if group.incident.closed?

    alert.alert_group = group
    group.incident
  end

  def create_incident(alert, outcome)
    severity = outcome_severity(outcome) || @source.resolve_severity(alert.fields["severity_raw"])
    raise ArgumentError, "no severity resolvable for alert #{alert.id} (set a workspace default severity)" unless severity

    resolver = target_resolver(alert)
    invitee_ids = resolver.memberships_for(outcome["invite"]).map(&:id)
    @resolution_notes = resolver.notes

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

  def attach(alert, incident)
    alert.incident = incident
    alert.save!
    record_incident_event(alert, IncidentEvent::ALERT_ATTACHED)
  end

  # notify_only posts the digest without an incident: to a channel, a member
  # (DM via their platform user id), or the owning team's channel resolved
  # from the catalog at fire time. Skips when a digest message already exists
  # (sweep retries after a partial failure must not double-post).
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

  def record_routing_failure(alert, error)
    Rails.logger.error({ event: "alert_routing.failed", alert_id: alert.id, error: error.message }.to_json)
    attempts = alert.routing_attempts + 1
    state = attempts >= MAX_ROUTING_ATTEMPTS ? Alert::ROUTING_FAILED : Alert::ROUTING_PENDING
    alert.update_columns(routing_attempts: attempts, routing_state: state, updated_at: Time.current)
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
    routing_policy&.content_match_fields || AlertGroup::DEFAULT_CONTENT_MATCH_FIELDS
  end

  def grouping_window
    (routing_policy&.grouping_window_minutes || AlertGroup::DEFAULT_WINDOW_MINUTES).minutes
  end

  def record_incident_event(alert, event_type)
    return unless alert.incident

    metadata = { alert_id: alert.id, title: alert.title, source: @source.name, event_count: alert.event_count }
    if @resolution_notes.present?
      metadata[:unresolved_targets] = @resolution_notes
      @resolution_notes = nil
    end

    alert.incident.incident_events.create!(event_type: event_type, metadata: metadata)
  end

  # Slack digest throttling: one message per alert that gets updated, never a
  # post per firing. Status transitions (attach/resolve) bypass the interval.
  # Runs under the alert's row lock so concurrent firings can't double-post,
  # and a failed attempt still stamps last_notified_at so a storm into a
  # broken channel doesn't retry on every delivery.
  def notify_digest(alert, force: false)
    alert.with_lock do
      channel_id = alert.incident&.channel_id || alert.channel_id
      next if channel_id.blank?
      next if !force && alert.last_notified_at.present? && alert.last_notified_at > NOTIFY_MIN_INTERVAL.ago

      adapter = WorkspaceAdapter.for(@workspace)

      begin
        if alert.channel_message_id.present?
          adapter.update_alert_message(channel_id: channel_id, message_id: alert.channel_message_id, alert: alert)
          alert.update!(last_notified_at: Time.current)
        else
          result = adapter.post_alert_message(channel_id: channel_id, alert: alert)
          alert.update!(channel_id: channel_id, channel_message_id: result[:message_id], last_notified_at: Time.current)
        end
      rescue AdapterError => e
        alert.update!(last_notified_at: Time.current)
        Rails.logger.warn({ event: "alert_digest.failed", alert_id: alert.id, error: e.message }.to_json)
      end
    end
  end
end
