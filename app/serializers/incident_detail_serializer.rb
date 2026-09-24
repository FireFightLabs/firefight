class IncidentDetailSerializer < BaseSerializer
  object_as :incident

  attributes(
    id: { type: :string },
    identifier: { type: :string },
    name: { type: :string },
    summary: { type: :string },
    source: { type: :string },
    channel_name: { type: :string, optional: true },
    channel_id: { type: :string, optional: true },
    is_private: { type: :boolean },
    is_test: { type: :boolean }
  )

  has_one :incident_severity, as: :severity, serializer: SeverityCompactSerializer
  has_one :incident_status, as: :status, serializer: StatusCompactSerializer

  # Nested output goes through the association DSL so the generator emits an import.
  # A bare `type :Name` is treated as hand-written and the import dangles.
  has_one :type, serializer: IncidentTypeCompactSerializer, optional: true do
    incident.incident_type
  end

  has_one :lead, serializer: ActorCompactSerializer, optional: true do
    incident.lead
  end

  # True while the first test incident is open, the page then points at the channel.
  type :boolean
  def onboarding_walkthrough
    incident.is_test? && incident.active? && incident.first_test_in_workspace?
  end

  # Every incident gets a channel, so a blank channel_name means creation has not finished.
  type :string
  def channel_label
    incident.channel_name.presence || incident.generated_channel_name
  end

  # The sentence a blocked control shows instead of vanishing. Nil while changes are allowed.
  type :string, optional: true
  def change_blocked_reason
    incident.change_blocked_reason
  end

  # Each control shows its own sentence, since they are blocked for different reasons,
  # an incident that is over or a channel still being created.
  type :string, optional: true
  def escalation_blocked_reason
    incident.escalation_blocked_reason
  end

  type :string, optional: true
  def invite_blocked_reason
    incident.invite_blocked_reason
  end

  type :string, optional: true
  def shoutout_blocked_reason
    incident.shoutout_blocked_reason
  end

  # Shared with claiming a runbook step, since a claim creates the action behind it.
  type :string, optional: true
  def action_blocked_reason
    incident.action_item_blocked_reason(IncidentAction::ACTION_TYPE_ACTION)
  end

  type :string, optional: true
  def followup_blocked_reason
    incident.action_item_blocked_reason(IncidentAction::ACTION_TYPE_FOLLOWUP)
  end

  # The lead picker needs the member id. Matching the chip's name breaks when two people share a display name.
  type :string, optional: true
  def lead_id
    incident.lead&.id
  end

  # Every configured role appears, held or not. The lead has its own field.
  has_many :roles, serializer: IncidentRoleAssignmentSerializer do
    incident.role_roster
  end

  has_many :subscribers, serializer: IncidentSubscriberSerializer do
    incident.subscribers
  end

  has_one :declared_by, serializer: ActorCompactSerializer, optional: true do
    incident.declared_by
  end

  type :string
  def declared_at
    incident.declared_at.utc.iso8601
  end

  type :string, optional: true
  def detected_at
    incident.detected_at&.utc&.iso8601
  end

  type :string, optional: true
  def resolved_at
    incident.resolved_at&.utc&.iso8601
  end

  type "Record<string, unknown>", optional: true
  def custom_fields
    incident.custom_fields_for_display.presence
  end

  has_many :alerts, serializer: IncidentAlertSerializer

  def alerts
    incident.alerts.includes(:alert_source).order(:received_at)
  end

  has_many :runbooks, serializer: IncidentRunbookSerializer

  def runbooks
    incident.incident_runbooks.includes(runbook: :runbook_steps).order(:created_at)
  end
end
