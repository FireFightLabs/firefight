# Registry of system fields the code depends on.
#
# A system field is a built-in incident attribute (severity, status, lead,
# ...) that:
#   - is always defined here in code,
#   - appears by default on the form-slugs listed in its `forms:` map,
#   - has its visibility/required-mode/position OVERRIDDEN by per-workspace
#     `IncidentFormField` rows (DB overlay). Absence of a DB row = default.
#
# Adding a new system field needs no migration: register it here with the
# `forms:` map, and every workspace's form editor + Slack modal picks it up
# automatically.
class IncidentSystemField
  KEY_NAME = "name"
  KEY_SUMMARY = "summary"
  KEY_SEVERITY = "severity"
  KEY_INCIDENT_TYPE = "incident_type"
  KEY_STATUS = "status"
  KEY_LEAD = "lead"
  KEY_VISIBILITY = "visibility"
  KEY_NEXT_UPDATE = "next_update"

  Definition = Struct.new(:key, :name, :description, :field_type, :forms, keyword_init: true) do
    # Returns the default required_mode for this field on the given form slug,
    # or nil if the field doesn't appear on that form by default.
    def required_mode_for(form_slug)
      forms[form_slug.to_s]
    end

    def appears_on?(form_slug)
      forms.key?(form_slug.to_s)
    end
  end

  # Listed in the order they should appear by default on each form. The
  # resolver iterates this list, picks definitions that apply to the
  # form slug, and uses encounter order as the default position.
  DEFINITIONS = [
    Definition.new(
      key: KEY_NAME,
      name: "Name",
      description: "Give a short description of what is happening.",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_INCIDENT_TYPE,
      name: "Incident Type",
      description: "Categorize the incident to improve reporting and routing.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_STATUS,
      name: "Status",
      description: "Move the incident to the correct lifecycle stage.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
      }
    ),
    Definition.new(
      key: KEY_SEVERITY,
      name: "Severity",
      description: "Communicate the expected impact and response urgency.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED,
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
      }
    ),
    Definition.new(
      key: KEY_SUMMARY,
      name: "Summary",
      description: "Capture the current understanding of what happened and the impact it had.",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_ACCEPT => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_VISIBILITY,
      name: "Visibility",
      description: "Who can see this incident.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_NEXT_UPDATE,
      name: "Next Update",
      description: "When to send the next status update reminder.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_LEAD,
      name: "Incident Lead",
      description: "The person coordinating the incident response.",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      forms: {
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
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

  # Default system fields for a given form slug, in default-position order.
  # The resolver applies DB overrides on top of this list.
  def self.defaults_for(form_slug)
    DEFINITIONS.select { |d| d.appears_on?(form_slug) }
  end
end
