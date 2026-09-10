# A workspace's IncidentFormField rows override visibility, required mode and position.
# Adding a field here needs no migration.
class IncidentSystemField
  KEY_NAME = "name"
  KEY_SUMMARY = "summary"
  KEY_SEVERITY = "severity"
  KEY_INCIDENT_TYPE = "incident_type"
  KEY_STATUS = "status"
  KEY_LEAD = "lead"
  KEY_VISIBILITY = "visibility"
  KEY_NEXT_UPDATE = "next_update"
  KEY_MESSAGE = "message"

  # How a ship mode lands on an IncidentFormField row. The resolver's unpersisted
  # default and the form service's stored row both read this, so they cannot disagree.
  SHIPS_AS = {
    IncidentFormField::REQUIRED_MODE_AVAILABLE => { visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN, required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL },
    IncidentFormField::REQUIRED_MODE_OPTIONAL => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL },
    IncidentFormField::REQUIRED_MODE_REQUIRED => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_REQUIRED },
    IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED }
  }.freeze

  # label, hint and placeholder live here rather than in the Slack adapter because
  # Slack and the form editor preview must render them identically.
  Definition = Struct.new(:key, :name, :label, :hint, :placeholder, :field_type, :forms, keyword_init: true) do
    # nil when the field does not appear on that form by default.
    def required_mode_for(form_slug)
      forms[form_slug.to_s]
    end

    def appears_on?(form_slug)
      forms.key?(form_slug.to_s)
    end

    # nil when the field does not appear on that form by default.
    def default_overlay_for(form_slug)
      mode = required_mode_for(form_slug)
      return nil unless mode

      IncidentSystemField::SHIPS_AS.fetch(mode).merge(
        field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
        system_field_key: key,
        position: IncidentSystemField.defaults_for(form_slug).index(self)
      )
    end
  end

  # Order here is the default position on every form.
  DEFINITIONS = [
    Definition.new(
      key: KEY_MESSAGE,
      name: "Message",
      label: "Message",
      hint: "What responders and stakeholders will read. This is the update itself.",
      placeholder: "What's happening at the moment? What are you doing next?",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      forms: {
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_REQUIRED
      }
    ),
    Definition.new(
      key: KEY_NEXT_UPDATE,
      name: "Next Update",
      label: "When will you provide the next update?",
      placeholder: "Select a time",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_NAME,
      name: "Name",
      label: "Incident name",
      hint: "Give a short description of what is happening.",
      placeholder: "Write something",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      # Required on declare because the channel is named from it once and cannot
      # be renamed. A blank name leaves a permanent inc-<date>-untitled channel.
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_REQUIRED,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    ),
    Definition.new(
      key: KEY_INCIDENT_TYPE,
      name: "Incident Type",
      label: "Incident Type",
      hint: "Categorize the incident to improve reporting and routing.",
      placeholder: "Select a type",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      # Off by default so the dialog stays short until a workspace wants categories.
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_AVAILABLE,
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_AVAILABLE
      }
    ),
    Definition.new(
      key: KEY_STATUS,
      name: "Status",
      label: "Status",
      hint: "Move the incident to the correct lifecycle stage.",
      placeholder: "Select status",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      forms: {
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_REQUIRED,
        IncidentForm::SLUG_CANCEL => IncidentFormField::REQUIRED_MODE_REQUIRED
      }
    ),
    Definition.new(
      key: KEY_SEVERITY,
      name: "Severity",
      label: "Severity",
      hint: "Communicate the expected impact and response urgency.",
      placeholder: "Select severity",
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
      label: "Summary",
      hint: "Your current understanding of what happened in the incident, and the impact it had. It's fine to go into detail here.",
      placeholder: "Think about what you'd like to read if you were coming to the incident fresh...",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      # Off on Update, where the Message field already carries what changed.
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_UPDATE => IncidentFormField::REQUIRED_MODE_AVAILABLE,
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL,
        IncidentForm::SLUG_CANCEL => IncidentFormField::REQUIRED_MODE_AVAILABLE
      }
    ),
    Definition.new(
      key: KEY_VISIBILITY,
      name: "Visibility",
      label: "Who should be able to see this incident?",
      hint: "Public incidents are visible to everyone in the workspace. Private incidents are only accessible to invited members.",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      # Off by default, most workspaces run every incident public.
      forms: {
        IncidentForm::SLUG_DECLARE => IncidentFormField::REQUIRED_MODE_AVAILABLE
      }
    ),
    Definition.new(
      key: KEY_LEAD,
      name: "Incident Lead",
      label: "Incident Lead",
      placeholder: "Select a person",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      forms: {
        IncidentForm::SLUG_RESOLVE => IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    )
  ].freeze

  DEFINITIONS_BY_KEY = DEFINITIONS.index_by(&:key).freeze

  # The fixed choices live here so Slack and the form editor read one copy.
  Choice = Data.define(:value, :label)

  VISIBILITY_CHOICES = [
    Choice.new(value: Incident::VISIBILITY_PUBLIC, label: "Everyone (public)"),
    Choice.new(value: Incident::VISIBILITY_PRIVATE, label: "Private")
  ].freeze

  NEXT_UPDATE_CHOICES = [
    Choice.new(value: "5", label: "5 minutes"),
    Choice.new(value: "15", label: "15 minutes"),
    Choice.new(value: "30", label: "30 minutes"),
    Choice.new(value: "60", label: "1 hour"),
    Choice.new(value: "180", label: "3 hours"),
    Choice.new(value: "1440", label: "1 day"),
    Choice.new(value: "10080", label: "7 days")
  ].freeze

  DEFAULT_NEXT_UPDATE_MINUTES = "15".freeze

  # nil when the answers come from the workspace's own records.
  def self.choices_for(key)
    case key
    when KEY_VISIBILITY then VISIBILITY_CHOICES
    when KEY_NEXT_UPDATE then NEXT_UPDATE_CHOICES
    end
  end

  def self.fetch(key)
    DEFINITIONS_BY_KEY.fetch(key)
  end

  def self.all
    DEFINITIONS
  end

  def self.valid_key?(key)
    DEFINITIONS_BY_KEY.key?(key)
  end

  def self.defaults_for(form_slug)
    DEFINITIONS.select { |d| d.appears_on?(form_slug) }
  end
end
