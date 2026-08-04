class IncidentFormSettingsSerializer < BaseSerializer
  object_as :incident_form

  attributes(
    slug: { type: :string },
    name: { type: :string },
    lifecycle_event: { type: :string },
    position: { type: :number }
  )

  # Persisted forms expose their DB id. Code-default forms (no DB row yet)
  # get a synthetic id (`default:<slug>`) — the frontend uses it verbatim,
  # and mutation controllers translate it back via
  # `Workspace#ensure_incident_form!` on first edit.
  type :string
  def id
    incident_form.id || "default:#{incident_form.slug}"
  end

  type :boolean
  def is_default
    incident_form.id.nil?
  end

  type :string, optional: true
  def description
    incident_form.description
  end

  # What a responder is actually asked, which is the resolved set minus the
  # fields an admin hid and the ones with nothing to ask.
  type :number
  def field_count
    resolved.count { |field| field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE && field.inactive_reason.nil? }
  end

  # Hidden fields included, greyed out in the editor. Leaving them out is what
  # made hiding a field a one-way door.
  type "IncidentFormFieldSettings[]"
  def fields
    IncidentFormFieldSettingsSerializer.many(resolved)
  end

  private

  # One resolve per form. Counting the visible fields with a second pass was a
  # whole extra round of queries for a number this list already answers.
  # Serializer instances are reused, so this memoizes into `memo` rather than
  # an ivar.
  def resolved
    memo.fetch(:resolved) { incident_form.resolved_fields(include_hidden: true) }
  end
end
