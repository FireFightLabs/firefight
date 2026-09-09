# Describes what an update changed, in the words a responder uses. The
# timeline card renders these, so a column name never reaches the screen and
# a timestamp arrives as a timestamp rather than a formatted string.
module IncidentUpdate::Changes
  extend ActiveSupport::Concern

  CHANGE_KIND_VALUE = "value"
  CHANGE_KIND_TEXT = "text"
  CHANGE_KIND_TIME = "time"
  CHANGE_KINDS = [ CHANGE_KIND_VALUE, CHANGE_KIND_TEXT, CHANGE_KIND_TIME ].freeze

  FIELD_STATUS = "status"
  FIELD_SEVERITY = "severity"
  FIELD_TYPE = "type"
  FIELD_LEAD = "lead"
  FIELD_DECLARED_BY = "declared_by"
  FIELD_NAME = "name"
  FIELD_SUMMARY = "summary"
  FIELD_VISIBILITY = "is_private"
  FIELD_NEXT_UPDATE_AT = "next_update_at"
  FIELD_RESOLVED_AT = "resolved_at"
  FIELD_CUSTOM_FIELDS = "custom_fields"

  TIME_FIELDS = [ "detected_at", "declared_at", FIELD_RESOLVED_AT, FIELD_NEXT_UPDATE_AT, "deleted_at" ].freeze
  TEXT_FIELDS = [ FIELD_SUMMARY ].freeze

  FIELD_LABELS = {
    FIELD_NEXT_UPDATE_AT => "Next update",
    FIELD_DECLARED_BY => "Declared by",
    FIELD_RESOLVED_AT => "Resolved at",
    "detected_at" => "Detected at",
    "declared_at" => "Declared at",
    "deleted_at" => "Deleted at",
    "identifier" => "Identifier",
    "sequence_number" => "Number",
    "platform_data" => "Platform data"
  }.freeze

  Change = Data.define(:field, :label, :kind, :before, :after)

  class_methods do
    # Fields the registry already names take their label from it, so the card
    # and the forms agree. Resolved on first use: the registry loads the
    # incident models while it builds, so reading it here at load time would
    # be a cycle.
    def system_field_keys
      @system_field_keys ||= {
        FIELD_STATUS => IncidentSystemField::KEY_STATUS,
        FIELD_SEVERITY => IncidentSystemField::KEY_SEVERITY,
        FIELD_TYPE => IncidentSystemField::KEY_INCIDENT_TYPE,
        FIELD_LEAD => IncidentSystemField::KEY_LEAD,
        FIELD_NAME => IncidentSystemField::KEY_NAME,
        FIELD_SUMMARY => IncidentSystemField::KEY_SUMMARY,
        FIELD_VISIBILITY => IncidentSystemField::KEY_VISIBILITY
      }.freeze
    end
  end

  # One entry per changed field, custom fields expanded to one entry each.
  # `field_definitions` maps slug to IncidentFieldDefinition for the custom
  # fields this update touched, loaded once per timeline by the caller.
  def changes_since(previous, field_definitions: {})
    changed_fields.flat_map do |field|
      if field == FIELD_CUSTOM_FIELDS
        custom_field_changes(previous, field_definitions)
      else
        [ Change.new(field: field, label: label_for(field), kind: kind_for(field),
                     before: previous&.display_value_for(field).presence, after: display_value_for(field).presence) ]
      end
    end
  end

  def display_value_for(field)
    case field.to_s
    when FIELD_STATUS then incident_status&.name
    when FIELD_SEVERITY then incident_severity&.name
    when FIELD_TYPE then incident_type&.name
    when FIELD_LEAD then lead&.actor_display_name
    when FIELD_DECLARED_BY then declared_by&.actor_display_name
    when FIELD_VISIBILITY then visibility_label
    when *TIME_FIELDS then public_send(field)&.iso8601
    else
      return nil unless respond_to?(field)
      public_send(field).to_s
    end
  end

  private

  def label_for(field)
    system_key = self.class.system_field_keys[field]
    return IncidentSystemField.fetch(system_key).name if system_key

    FIELD_LABELS.fetch(field) { field.humanize }
  end

  def kind_for(field)
    return CHANGE_KIND_TEXT if TEXT_FIELDS.include?(field)
    return CHANGE_KIND_TIME if TIME_FIELDS.include?(field)

    CHANGE_KIND_VALUE
  end

  def visibility_label
    value = is_private ? Incident::VISIBILITY_PRIVATE : Incident::VISIBILITY_PUBLIC
    IncidentSystemField::VISIBILITY_CHOICES.find { |choice| choice.value == value }.label
  end

  # The snapshot stores labels, not ids, so a renamed or deleted option still
  # reads the way it did at the time.
  def custom_field_changes(previous, field_definitions)
    before = previous&.custom_fields || {}
    after = custom_fields
    (before.keys | after.keys).filter_map do |slug|
      next if before[slug] == after[slug]

      definition = field_definitions[slug]
      kind = definition&.field_type == IncidentFieldDefinition::TYPE_TEXT ? CHANGE_KIND_TEXT : CHANGE_KIND_VALUE
      Change.new(field: "#{FIELD_CUSTOM_FIELDS}.#{slug}", label: definition&.name || slug.humanize, kind: kind,
                 before: custom_value_text(before[slug]), after: custom_value_text(after[slug]))
    end
  end

  def custom_value_text(value)
    Array.wrap(value).map(&:to_s).join(", ").presence
  end
end
