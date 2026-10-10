# Pages whoever a run an alert started found on call, by escalating the incident to them with what Halon found, once the
# team lets Halon page. Escalating is how anyone is paged here, so the person gets the same message and reminder as when
# a responder escalates, and approvals for the incident can reach them as whoever is on call.
class Investigation::Paging
  REASON_LIMIT = 3_000

  def self.page!(investigation)
    finding = investigation.finding
    return unless investigation.pages_on_call? && !investigation.rehearsal? && finding&.page_member
    return unless finding.claim_page!

    new(investigation).page!(finding.page_member)
  end

  def initialize(investigation)
    @investigation = investigation
    @incident = investigation.incident
  end

  def page!(member)
    @investigation.record_paging!(member) do
      IncidentLifecycleService.new(@investigation.workspace).escalate(@incident, escalated_to: member, reason: reason, changed_by: @investigation.acting_principal)
    end
  rescue Incident::NotActive => error
    Rails.logger.info({ event: "paging.incident_not_active", investigation_id: @investigation.id, reason: error.message }.to_json)
  end

  private

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
