# Raises pages in an on-call tool for incidents and keeps each in step with its incident both ways (Incident::Page).
# Every call to the tool is made as Firefight paging through the gateway, so approval rules hold it and the activity
# log names whose change it carried. A change the tool sends back moves the page only from where it was, and the side
# that loses that race does nothing, so a change made here never comes back as a second one.
class OnCallSyncService
  RAISE = "raise".freeze
  ACKNOWLEDGE = "acknowledge".freeze
  RESOLVE = "resolve".freeze

  Paging = Integrations::Paging
  Page = Incident::Page

  def initialize(workspace)
    @workspace = workspace
  end

  # Why a page cannot be raised on this incident through this connection, or nil.
  def page_blocked_reason(incident, integration)
    incident.page_blocked_reason || connection_blocked_reason(integration)
  end

  # Raises a page now, on target through the connection, and answers the page, triggered once the tool has it. One the
  # tool refused is failed, and one an approval rule holds waits, with why in its sync_note either way.
  def raise_page!(incident, integration:, target:, details:, by:, paged_member: nil, paged_email: nil)
    blocked = incident.page_blocked_reason
    raise Incident::NotActive, blocked if blocked

    page = incident.pages.create!(
      workspace: @workspace, integration: integration, origin: Page::ORIGIN_RAISED, state: Page::STATE_RAISING, target: target.to_s.strip,
      title: "#{incident.identifier} #{incident.name}".truncate(255), details: details.to_s.truncate(Page::DETAILS_LIMIT),
      requested_by: by, paged_member: paged_member, paged_email: paged_email.presence
    )
    raise_now(page, by)
    page.reload
  end

  # A call parked for approval, or a change queued from here, run by OnCallSyncJob.
  def perform(operation, page, by, approval_id: nil)
    operation == RAISE ? raise_now(page, by, approval_id) : push_now(operation, page, by, approval_id)
  end

  # The incident was resolved here, so every page still open in its tool is resolved there too.
  def incident_closed(incident, by:)
    incident.pages.open_pages.find_each do |page|
      next unless page.move!(from: Page::OPEN_STATES, to: Page::STATE_RESOLVED, resolved_at: Time.current)

      OnCallSyncJob.perform_later(operation: RESOLVE, page: page, by: by)
    end
  end

  # Someone paged for the incident said they have it, so its pages stop paging anyone else.
  def escalation_acknowledged(incident, by:)
    incident.pages.where(state: Page::STATE_TRIGGERED).find_each do |page|
      next unless page.move!(from: Page::STATE_TRIGGERED, to: Page::STATE_ACKNOWLEDGED, acknowledged_at: Time.current)

      OnCallSyncJob.perform_later(operation: ACKNOWLEDGE, page: page, by: by)
    end
  end

  # An alert from an on-call tool joined an incident, so the page behind it is kept in step from now on.
  def alert_attached(alert)
    Page.adopt!(alert) if alert.incident && Paging.reported_by?(alert.alert_source.provider)
  end

  # The page Firefight raised that an alert from the tool reports, which the alert joins rather than opening another
  # incident. key is the one the tool sent back, or nil.
  def raised_page_for(alert, key)
    page_id = Paging.page_id_of(key)
    pages = Page.raised.where(workspace: @workspace)
    (page_id && pages.find_by(id: page_id)) || pages.find_by(external_id: alert.fingerprint)
  end

  # What happened to a page in its tool, from the alert source's webhook, applied in a job.
  def received(source, event)
    OnCallEventJob.perform_later(source: source, event: event.to_job)
  end

  def apply(source, event)
    page = Page.for_event(@workspace, event)
    return unless page

    page.update!(alert_source: source) if page.alert_source.nil?
    page.update!(external_id: event.external_id) if page.external_id.nil? && event.external_id.present?
    return if event.id.present? && page.incident.incident_events.where("metadata->>'tool_event_id' = ?", event.id).exists?

    person = event.actor_email.present? ? @workspace.workspace_memberships.resolve(event.actor_email) : nil
    told = { actor: person, by_name: (event.actor_name unless person), subject: page.label, tool_event_id: event.id }

    case event.kind
    when Paging::EVENT_ACKNOWLEDGED then acknowledged_there(page, person, told)
    when Paging::EVENT_ESCALATED then page.record_event!(IncidentEvent::PAGE_ESCALATED, **told, message: event.note)
    when Paging::EVENT_NOTED then page.record_event!(IncidentEvent::PAGE_NOTED, **told, message: event.note)
    when Paging::EVENT_RESOLVED then resolved_there(page, person, event, told)
    end
  end

  # An approver decided on a call parked for a page. Approved, it runs again with the approval. Declined, the page says
  # so and so does the incident.
  def decided(approval, payload)
    page = Page.where(workspace: @workspace).find_by(id: payload["page_id"])
    return unless page

    by = GlobalID::Locator.locate(payload["by"])
    if approval.approved?
      OnCallSyncJob.perform_later(operation: payload["operation"], page: page, by: by, approval_id: approval.id)
      return
    end

    declined = "#{approval.approver&.actor_display_name || 'A workspace admin'} declined it."
    if payload["operation"] == RAISE
      return unless page.move!(from: Page::STATE_AWAITING_APPROVAL, to: Page::STATE_FAILED, sync_note: declined)

      page.record_event!(IncidentEvent::PAGE_FAILED, subject: raise_subject(page), message: declined)
    else
      page.update!(sync_note: declined)
      page.record_event!(IncidentEvent::PAGE_SYNC_FAILED, subject: page.label, message: "#{operation_words(payload['operation'])} #{declined}")
    end
  end

  private

  def connection_blocked_reason(integration)
    return "Connect an on-call tool under Integrations to page through one." if integration.nil?
    return "#{integration.display_name} cannot raise a page." unless Paging.pages?(integration.provider)

    @workspace.paging_blocked_reason(integration)
  end

  def raise_now(page, by, approval_id = nil)
    return unless Page::NOT_YET_RAISED.include?(page.state)

    raised = session(page, by, approval_id).page(title: page.title, details: page.details, target: page.target, key: page.key)
    won = page.move!(from: Page::NOT_YET_RAISED, to: Page::STATE_TRIGGERED, external_id: raised.external_id, reference: raised.reference,
                     url: raised.url, sync_note: nil)
    return unless won

    page.record_event!(IncidentEvent::PAGE_RAISED, actor: by, subject: raise_subject(page), message: page.details,
                                                   paged_member_id: page.paged_member_id, paged_email: page.paged_email)
    OnCallApprovalsJob.perform_later(page.incident_id, page.paged_member_id) if page.paged_member_id
  rescue AbilityGateway::PendingApproval => pending
    park(page, pending.approval, RAISE, by)
    page.move!(from: Page::STATE_RAISING, to: Page::STATE_AWAITING_APPROVAL,
               sync_note: "Paging #{page.target} through #{page.tool_name} is waiting for approval.")
  rescue AbilityGateway::Denied => denied
    refused(page, by, denied_words(page, denied))
  rescue Integrations::Error => error
    refused(page, by, error.message)
  end

  def refused(page, by, words)
    return unless page.move!(from: Page::NOT_YET_RAISED, to: Page::STATE_FAILED, sync_note: words)

    page.record_event!(IncidentEvent::PAGE_FAILED, actor: by, subject: raise_subject(page), message: words)
  end

  def push_now(operation, page, by, approval_id)
    pager = session(page, by, approval_id)
    operation == ACKNOWLEDGE ? pager.acknowledge(page.external_id, key: page.key) : pager.resolve(page.external_id, key: page.key)
    page.update!(sync_note: nil) if page.sync_note
  rescue AbilityGateway::PendingApproval => pending
    park(page, pending.approval, operation, by)
    page.update!(sync_note: "#{operation_words(operation)} is waiting for approval.")
  rescue AbilityGateway::Denied => denied
    not_taken(page, operation, denied_words(page, denied))
  rescue Integrations::Error => error
    not_taken(page, operation, error.message)
  end

  # The page keeps the state Firefight gave it, since the incident moved on here, and the incident says the tool did not
  # follow so someone does it there by hand.
  def not_taken(page, operation, words)
    page.update!(sync_note: words)
    page.record_event!(IncidentEvent::PAGE_SYNC_FAILED, subject: page.label, message: "#{operation_words(operation)} did not happen. #{words}")
  end

  def acknowledged_there(page, person, told)
    return unless page.move!(from: Page::STATE_TRIGGERED, to: Page::STATE_ACKNOWLEDGED, acknowledged_at: Time.current)

    page.record_event!(IncidentEvent::PAGE_ACKNOWLEDGED, **told)
    acknowledge_escalations(page.incident, person) if person
  end

  # Whoever acknowledged the page in the tool has the escalations here that asked them, so those stop reminding them.
  def acknowledge_escalations(incident, person)
    escalations = incident.incident_events.where(event_type: IncidentEvent::INCIDENT_ESCALATED)
                          .select { |event| event.metadata.to_h["escalated_to_member_id"] == person.id && !event.escalation_acknowledged? }
    service = IncidentLifecycleService.new(@workspace)
    escalations.each do |escalation|
      service.acknowledge_escalation(incident, escalation, platform_user_id: person.platform_user_id, acknowledged_by: person)
    end
  end

  # The incident is resolved here once its last open page is, and only when a person resolved it there. A monitor
  # resolving its own alert never closes an incident, since closing is a person's decision.
  def resolved_there(page, person, event, told)
    return unless page.move!(from: Page::STATES - [ Page::STATE_RESOLVED ], to: Page::STATE_RESOLVED, resolved_at: Time.current)

    page.record_event!(IncidentEvent::PAGE_RESOLVED, **told)
    incident = page.incident
    return if !event.by_person || incident.terminal? || incident.pages.where.not(state: [ Page::STATE_RESOLVED, Page::STATE_FAILED ]).exists?

    IncidentLifecycleService.new(@workspace).change_status(incident, { incident_status: @workspace.default_closed_status },
                                                           changed_by: person || SystemAgent.paging)
  rescue Incident::NotActive => error
    Rails.logger.info({ event: "on_call_sync.close_skipped", page_id: page.id, reason: error.message }.to_json)
  end

  # The connection the page is kept in step through. A page an alert brought in is the one connection of its tool that
  # knows it, asked the first time it is needed.
  def session(page, by, approval_id)
    integration = page.integration&.then { |known| known.operational? ? known : nil } || connection_for(page, by)
    raise Paging::Failed, "No connection to #{page.tool_name} can reach #{page.label}. Connect it under Integrations." unless integration

    Paging.session(integration) do |tool, arguments, &run|
      page.authorize_pager_call!(tool, by: by, arguments: arguments, approval_id: approval_id) { run.call }
    end
  end

  def connection_for(page, by)
    return nil unless page.alert_source && page.external_id

    candidates = Paging.connections_for_source(@workspace, page.alert_source.provider).select(&:operational?)
    found = if candidates.one? then candidates.first
    else
      candidates.find do |integration|
        Paging.session(integration) { |tool, arguments, &run| page.authorize_pager_call!(tool, by: by, arguments: arguments) { run.call } }
              .knows?(page.external_id)
      end
    end
    page.update!(integration: found) if found
    found
  end

  def park(page, approval, operation, by)
    approval.update!(resume_payload: { kind: ApprovalResumption::KIND_PAGING, page_id: page.id, operation: operation, by: by&.to_global_id&.to_s })
  end

  def raise_subject(page) = "#{page.target} through #{page.tool_name}"

  def operation_words(operation)
    case operation
    when RAISE then "Raising the page"
    when ACKNOWLEDGE then "Acknowledging it there"
    else "Resolving it there"
    end
  end

  def denied_words(page, denied)
    "Firefight paging may not use #{denied.action_key}. #{page.integration && @workspace.paging_blocked_reason(page.integration)}".strip
  end
end
