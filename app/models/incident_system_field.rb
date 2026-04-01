class IncidentSystemField
  KEY_NAME = "name"
  KEY_SUMMARY = "summary"
  KEY_SEVERITY = "severity"
  KEY_INCIDENT_TYPE = "incident_type"
  KEY_STATUS = "status"

  Definition = Struct.new(:key, :name, :description, :field_type, :required_mode, keyword_init: true)

  DEFINITIONS = [
    Definition.new(
      key: KEY_NAME,
      name: "Name",
      description: "Give a short description of what is happening.",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    ),
    Definition.new(
      key: KEY_INCIDENT_TYPE,
      name: "Incident Type",
      description: "Categorize the incident to improve reporting and routing.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    ),
    Definition.new(
      key: KEY_SEVERITY,
      name: "Severity",
      description: "Communicate the expected impact and response urgency.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      required_mode: IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
    ),
    Definition.new(
      key: KEY_SUMMARY,
      name: "Summary",
      description: "Capture the current understanding of what happened and the impact it had.",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    ),
    Definition.new(
      key: KEY_STATUS,
      name: "Status",
      description: "Move the incident to the correct lifecycle stage.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      required_mode: IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
    )
  ].freeze

  DEFINITIONS_BY_KEY = DEFINITIONS.index_by(&:key).freeze

  def self.fetch(key)
    DEFINITIONS_BY_KEY.fetch(key)
  end

  def self.all
    DEFINITIONS
  end

  def self.valid_key?(key)
    DEFINITIONS_BY_KEY.key?(key)
  end
end
