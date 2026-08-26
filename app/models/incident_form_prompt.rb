# What a lifecycle form is asking, ready for a surface that renders its own
# inputs rather than being handed Block Kit.
#
# The resolver decides which fields a responder sees. This adds the part Slack
# gets from its own pickers: the choices behind each select, and the value the
# incident already holds. Slack asks the workspace for a users_select and a
# static_select of statuses. A browser has to be told.
#
# It reads the same `resolve(slug, context:)` that `validate_submission` reads,
# so a field cannot be rendered here and rejected there, or the reverse.
class IncidentFormPrompt
  # Answering one of these changes which fields the form asks for, so the
  # surface re-resolves instead of guessing. Status drives Next Update through
  # `moot_for_context?`, and every one of them can drive a custom field's
  # condition.
  DISPATCHING_KEYS = [
    IncidentSystemField::KEY_STATUS,
    IncidentSystemField::KEY_SEVERITY,
    IncidentSystemField::KEY_INCIDENT_TYPE,
    IncidentSystemField::KEY_VISIBILITY
  ].freeze

  Choice = Data.define(:value, :label)
  Field = Data.define(:key, :label, :hint, :placeholder, :input, :required, :dispatches, :choices, :value)

  # Every input a browser has to render. Mapped from the field's type rather
  # than passed through, so the frontend switches on a closed set.
  INPUT_TEXT = "text"
  INPUT_LONG_TEXT = "long_text"
  INPUT_NUMBER = "number"
  INPUT_LINK = "link"
  INPUT_SELECT = "select"
  INPUT_MULTI_SELECT = "multi_select"
  INPUT_PERSON = "person"
  INPUTS = [ INPUT_TEXT, INPUT_LONG_TEXT, INPUT_NUMBER, INPUT_LINK, INPUT_SELECT, INPUT_MULTI_SELECT, INPUT_PERSON ].freeze

  LONG_TEXT_KEYS = [ IncidentSystemField::KEY_SUMMARY, IncidentSystemField::KEY_MESSAGE ].freeze

  def initialize(workspace, incident:, form_slug:, answers: {})
    @workspace = workspace
    @incident = incident
    @form_slug = form_slug
    @answers = (answers || {}).stringify_keys
  end

  def fields
    resolver.resolve(@form_slug, context: context).map do |form_field|
      form_field.system? ? system_field(form_field) : custom_field(form_field)
    end
  end

  # The context the fields were resolved against. Validating a submission has
  # to read the same one, or a field is shown and then rejected.
  def context
    IncidentConditionEvaluator.context_for(@incident, workspace: @workspace, answers: @answers)
  end

  private

  def resolver
    @resolver ||= IncidentFormResolver.new(@workspace)
  end

  def system_field(form_field)
    key = form_field.system_field_key
    definition = IncidentSystemField.fetch(key)

    Field.new(
      key: key,
      label: definition.label,
      hint: definition.hint,
      placeholder: definition.placeholder,
      input: system_input(key, definition),
      required: required?(form_field),
      dispatches: DISPATCHING_KEYS.include?(key),
      choices: system_choices(key),
      value: system_value(key)
    )
  end

  def system_input(key, definition)
    return INPUT_PERSON if key == IncidentSystemField::KEY_LEAD
    return INPUT_LONG_TEXT if LONG_TEXT_KEYS.include?(key)
    return INPUT_SELECT if definition.field_type == IncidentFieldDefinition::TYPE_SINGLE_SELECT

    INPUT_TEXT
  end

  def system_choices(key)
    fixed = IncidentSystemField.choices_for(key)
    return fixed.map { |choice| Choice.new(value: choice.value, label: choice.label) } if fixed

    case key
    when IncidentSystemField::KEY_STATUS then status_choices
    when IncidentSystemField::KEY_SEVERITY then slug_choices(@workspace.incident_severities.active.by_rank)
    when IncidentSystemField::KEY_INCIDENT_TYPE then slug_choices(@workspace.incident_types.active.ordered)
    when IncidentSystemField::KEY_LEAD then member_choices
    end
  end

  # A terminal form offers only the statuses its transition targets. Everything
  # else offers the live ones plus whatever the incident currently holds, so a
  # reopened incident's own status is never missing from its own form.
  def status_choices
    stage = IncidentFormResolver::TERMINAL_STAGE_BY_FORM[@form_slug]
    return slug_choices(@workspace.incident_statuses.active.in_stage(stage).ordered) if stage

    slug_choices(@workspace.incident_statuses.active.ordered)
  end

  def slug_choices(scope)
    scope.map { |record| Choice.new(value: record.slug, label: record.name) }
  end

  # The dashboard picks a person from the workspace roster, where Slack opens
  # its own users_select. Ids rather than slugs, since a membership has none.
  def member_choices
    @workspace.workspace_memberships.includes(:user).map do |member|
      Choice.new(value: member.id, label: member.display_name)
    end.sort_by(&:label)
  end

  def system_value(key)
    return @answers[key] if @answers.key?(key)
    return nil if @incident.nil?

    case key
    when IncidentSystemField::KEY_NAME then @incident.name
    when IncidentSystemField::KEY_SUMMARY then @incident.summary
    when IncidentSystemField::KEY_STATUS then @incident.incident_status&.slug
    when IncidentSystemField::KEY_SEVERITY then @incident.incident_severity&.slug
    when IncidentSystemField::KEY_INCIDENT_TYPE then @incident.incident_type&.slug
    when IncidentSystemField::KEY_LEAD then @incident.lead&.id
    when IncidentSystemField::KEY_VISIBILITY then answered_visibility
    when IncidentSystemField::KEY_NEXT_UPDATE then IncidentSystemField::DEFAULT_NEXT_UPDATE_MINUTES
    end
  end

  def custom_field(form_field)
    definition = form_field.incident_field_definition

    Field.new(
      key: definition.slug,
      label: definition.name,
      hint: definition.description,
      placeholder: nil,
      input: custom_input(definition),
      required: required?(form_field),
      dispatches: true,
      choices: definition.selectable? ? definition.selectable_values.map { |value, label| Choice.new(value: value, label: label) } : nil,
      value: @answers.fetch(definition.slug) { @incident&.custom_fields&.dig(definition.slug) }
    )
  end

  def custom_input(definition)
    return INPUT_MULTI_SELECT if definition.multi_valued?
    return INPUT_SELECT if definition.selectable?

    case definition.field_type
    when IncidentFieldDefinition::TYPE_NUMBER then INPUT_NUMBER
    when IncidentFieldDefinition::TYPE_LINK then INPUT_LINK
    else INPUT_TEXT
    end
  end

  def required?(form_field)
    form_field.required_mode.in?([
      IncidentFormField::REQUIRED_MODE_REQUIRED,
      IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
    ])
  end
end
