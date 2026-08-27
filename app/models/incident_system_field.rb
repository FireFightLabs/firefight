# Registry of system fields the code depends on.
#
# A system field is a built-in incident attribute (severity, status, lead,
# ...) that:
#   - is always defined here in code,
#   - appears by default on the form-slugs listed in its `forms:` map,
#   - has its visibility/required-mode/position OVERRIDDEN by per-workspace
#     `IncidentFormField` rows (DB overlay). Absence of a DB row = default.
#
# Adding a new system field needs no migration. Register it here with the
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
  KEY_MESSAGE = "message"

  # `name` is the short handle for prose: flash messages, "Severity is
  # required", the settings row. `label`, `hint`, and `placeholder` are what a
  # responder actually reads above and inside the input, and are rendered
  # identically by Slack and by the form editor's preview. Keeping them here
  # rather than in the Slack adapter is what stops the two surfaces drifting.
  # How a ship mode from the registry lands on an IncidentFormField row. The
  # one table the resolver's unpersisted default and the form service's
  # materialized row both read, so the two can never disagree.
  SHIPS_AS = {
    IncidentFormField::REQUIRED_MODE_AVAILABLE => { visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN, required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL },
    IncidentFormField::REQUIRED_MODE_OPTIONAL => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL },
    IncidentFormField::REQUIRED_MODE_REQUIRED => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_REQUIRED },
    IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED => { visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE, required_mode: IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED }
  }.freeze

  Definition = Struct.new(:key, :name, :label, :hint, :placeholder, :field_type, :forms, keyword_init: true) do
    # Returns the default required_mode for this field on the given form slug,
    # or nil if the field doesn't appear on that form by default.
    def required_mode_for(form_slug)
      forms[form_slug.to_s]
    end

    def appears_on?(form_slug)
      forms.key?(form_slug.to_s)
    end

    # The row attributes this field ships with on a form, position included,
    # or nil when it does not appear there by default.
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

  # Listed in the order they should appear by default on each form. The
  # resolver iterates this list, picks definitions that apply to the
  # form slug, and uses encounter order as the default position.
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
      # Required on declare because the channel is named from it once, at
      # creation, and cannot be renamed later. A blank name leaves a permanent
      # inc-<date>-untitled channel and "Untitled Incident" everywhere the
      # incident is referred to. The API already requires it and alerts derive
      # it from the alert title, so this is the only path that let it through.
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
      # Off by default on both. Categorizing is worth having, but not at the
      # cost of a longer dialog before a workspace has decided it wants it.
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
      # Off by default: most workspaces run every incident public, and the
      # ones that do not can turn this on.
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

  # What the two fixed-choice system fields offer. They live here for the same
  # reason label, hint and placeholder do. Both surfaces read them, and a copy
  # kept in one of them is a copy that drifts. The workspace's own records
  # answer the rest (statuses, severities, types, people).
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

  # The fixed choices for a key, or nil when the answers come from the
  # workspace's own records instead.
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

  # Default system fields for a given form slug, in default-position order.
  # The resolver applies DB overrides on top of this list.
  def self.defaults_for(form_slug)
    DEFINITIONS.select { |d| d.appears_on?(form_slug) }
  end
end
