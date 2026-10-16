# A page in an on-call tool tied to an incident, kept in step both ways (OnCallSyncService). Firefight raises one when
# Halon or a person pages through the tool, and an alert from the tool brings one in when it joins the incident.
# Acknowledging or resolving on either side reaches the other. Every move of its state is one guarded update, and the
# side that loses the race does nothing, which is what stops a change Firefight made from coming back as an event and
# being applied a second time.
class Incident::Page < ApplicationRecord
  include Incident::LiveSignal

  shown_on_incident_page Incident::LiveSignal::PART_INCIDENT

  ORIGIN_RAISED = "raised".freeze
  ORIGIN_ALERT = "alert".freeze
  ORIGINS = [ ORIGIN_RAISED, ORIGIN_ALERT ].freeze

  # Before the tool has it: being raised, held for an approval, or refused.
  STATE_RAISING = "raising".freeze
  STATE_AWAITING_APPROVAL = "awaiting_approval".freeze
  STATE_FAILED = "failed".freeze
  STATE_TRIGGERED = Integrations::Paging::STATE_TRIGGERED
  STATE_ACKNOWLEDGED = Integrations::Paging::STATE_ACKNOWLEDGED
  STATE_RESOLVED = Integrations::Paging::STATE_RESOLVED
  STATES = [ STATE_RAISING, STATE_AWAITING_APPROVAL, STATE_FAILED, STATE_TRIGGERED, STATE_ACKNOWLEDGED, STATE_RESOLVED ].freeze
  # Still paging or being worked in the tool, so a change on the incident reaches it.
  OPEN_STATES = [ STATE_TRIGGERED, STATE_ACKNOWLEDGED ].freeze
  NOT_YET_RAISED = [ STATE_RAISING, STATE_AWAITING_APPROVAL ].freeze

  DETAILS_LIMIT = 3_000

  belongs_to :workspace
  belongs_to :incident
  # The connection it is kept in step through. A page an alert brought in finds it the first time it is needed.
  belongs_to :integration, optional: true
  # The alert source whose webhook reports what happens to it in the tool.
  belongs_to :alert_source, optional: true
  # Whoever the tool had on call when Halon paged, when they are a member here.
  belongs_to :paged_member, class_name: "WorkspaceMembership", optional: true
  # Whoever asked for the page, a person, an agent or Halon's investigator.
  belongs_to :requested_by, polymorphic: true, optional: true

  validates :origin, inclusion: { in: ORIGINS }
  validates :state, inclusion: { in: STATES }

  scope :open_pages, -> { where(state: OPEN_STATES) }
  scope :raised, -> { where(origin: ORIGIN_RAISED) }

  # The key Firefight raised it with, which the tool sends back with every change to it.
  def key = Integrations::Paging.key_for(id)

  STATE_WORDS = {
    STATE_RAISING => "Being raised", STATE_AWAITING_APPROVAL => "Waiting for approval", STATE_FAILED => "Not raised",
    STATE_TRIGGERED => "Paging", STATE_ACKNOWLEDGED => "Acknowledged", STATE_RESOLVED => "Resolved"
  }.freeze

  def state_words = STATE_WORDS.fetch(state)

  # What the tool is called here, the connection's name or else the alert source's.
  def tool_name = integration&.display_name || alert_source&.name || "the on-call tool"

  # The page as a person reads it, such as "#42 in PagerDuty", or before the tool has it, what it is being raised on.
  def label
    return "a page to #{target} in #{tool_name}" if external_id.blank? && target.present?

    "#{reference.presence || title.presence || 'the page'} in #{tool_name}"
  end

  # Moves the state on only from where it was, so two workers, or a change and its echo from the tool, never both act.
  # False when it had moved.
  def move!(from:, to:, **columns)
    won = self.class.where(id: id, state: Array(from)).update_all(state: to, updated_at: Time.current, **columns)
    reload
    signal_incident_page if won == 1
    won == 1
  end

  # A page an alert from an on-call tool brought into the incident. The tool's id is the alert's fingerprint, so a page
  # Firefight raised is found again rather than kept twice, and an alert that moved to another incident takes it along.
  def self.adopt!(alert)
    page = find_by(workspace_id: alert.workspace_id, external_id: alert.fingerprint)
    return page.tap { page.update!(incident: alert.incident, alert_source: page.alert_source || alert.alert_source) } if page

    create!(workspace_id: alert.workspace_id, incident: alert.incident, alert_source: alert.alert_source, origin: ORIGIN_ALERT,
            state: STATE_TRIGGERED, external_id: alert.fingerprint, title: alert.title)
  rescue ActiveRecord::RecordNotUnique
    find_by!(workspace_id: alert.workspace_id, external_id: alert.fingerprint)
  end

  # The page an event from the tool is about, found by the key Firefight raised it with or else by the tool's id.
  def self.for_event(workspace, event)
    page_id = Integrations::Paging.page_id_of(event.key)
    (page_id && where(workspace: workspace).find_by(id: page_id)) || where(workspace: workspace).find_by(external_id: event.external_id)
  end

  # Every call to the tool is made as Firefight paging, which holds exactly the tools paging and keeping pages in step
  # need, never a person's reach. Approval rules still apply, and the activity log names whose change it carried.
  def authorize_pager_call!(tool, by:, arguments:, approval_id: nil, &)
    AbilityGateway.authorize!(
      principal: SystemAgent.paging, action_key: tool.action_key, workspace: workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_PAGING, approval_id: approval_id, incident_id: incident_id,
                 triggered_by_label: change_label(by) }.compact, &
    )
  end

  # The investigator reads who is on call through the connection's read pack, like any read a run makes.
  def self.authorize_on_call_read!(tool, investigation:, arguments:, &)
    AbilityGateway.authorize!(
      principal: investigation.acting_principal, action_key: tool.action_key, workspace: investigation.workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_INVESTIGATION, incident_id: investigation.incident&.id,
                 triggered_by_label: "Who is on call, for #{investigation.incident&.identifier || 'the run'}" }, &
    )
  end

  # Writes what happened to the page on the incident's timeline. actor is who did it here, nil for the tool or its
  # people, whose name metadata carries.
  def record_event!(event_type, actor: nil, **metadata)
    incident.incident_events.create!(
      event_type: event_type, actor: actor,
      metadata: { page_id: id, page: label, tool: tool_name, url: url, title: title }.merge(metadata).compact
    )
  end

  # Whose change a call to the tool carries, as the activity log shows it.
  def change_label(by)
    what = "#{label}, for #{incident.identifier}"
    by ? "#{by.actor_display_name}, on #{what}" : what.upcase_first
  end
end
