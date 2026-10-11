# Pages whoever a run an alert started found on call, with what Halon found, once the team lets Halon page. With an
# on-call tool connected the page is raised there, on the service or team the run named, so the tool's own escalation
# wakes them and the page is kept in step with the incident (OnCallSyncService). Without one, the incident is escalated
# to them, which is how anyone is paged here, so the person gets the same message and reminder as when a responder
# escalates. Either way approvals for the incident can reach them as whoever is on call. A page the tool would not take
# falls back to escalating here, since someone has to wake up.
class Investigation::Paging
  REASON_LIMIT = 3_000

  def self.page!(investigation)
    finding = investigation.finding
    return unless investigation.pages_on_call? && !investigation.rehearsal? && (finding&.page_member || finding&.page_integration)
    return unless finding.claim_page!

    new(investigation).page!(finding)
  end

  def initialize(investigation)
    @investigation = investigation
    @incident = investigation.incident
  end

  def page!(finding)
    page = raise_in_tool(finding) if finding.page_integration
    return if page && page.state == Incident::Page::STATE_TRIGGERED
    return unless finding.page_member

    escalate!(finding.page_member, page)
  rescue Incident::NotActive => error
    Rails.logger.info({ event: "paging.incident_not_active", investigation_id: @investigation.id, reason: error.message }.to_json)
  end

  private

  def raise_in_tool(finding)
    OnCallSyncService.new(@investigation.workspace).raise_page!(
      @incident, integration: finding.page_integration, target: finding.page_target, details: reason, by: @investigation.acting_principal,
                 paged_member: finding.page_member, paged_email: finding.page_email
    )
  end

  def escalate!(member, page)
    why = [ reason, (page.sync_note if page) ].compact.join("\n\n").truncate(REASON_LIMIT)
    @investigation.record_paging!(member) do
      IncidentLifecycleService.new(@investigation.workspace).escalate(@incident, escalated_to: member, reason: why, changed_by: @investigation.acting_principal)
    end
  end

  # What Halon found and what happens next, so the person paged knows before they open the channel.
  def reason
    finding = @investigation.finding
    plan = finding.remediation_plan
    lines = [ "Halon looked at this alert. #{finding.summary}" ]
    lines << if plan.nil? then nil
    elsif plan.unattended? then "Halon applied the fix on its own, under an unattended rule: #{plan.summary}"
    else "Proposed fix, waiting for someone to apply it: #{plan.summary}"
    end
    lines.compact.join("\n\n").truncate(REASON_LIMIT)
  end
end
