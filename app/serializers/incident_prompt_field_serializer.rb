# One question on a lifecycle form, as the dashboard renders it. The settings
# serializer next to this one describes how a field is configured. This one
# describes what a responder is being asked right now, choices included.
class IncidentPromptFieldSerializer < BaseSerializer
  object_as :field

  INPUT_UNION = IncidentFormPrompt::INPUTS.map(&:inspect).join(" | ")

  attributes(
    key: { type: :string },
    label: { type: :string },
    required: { type: :boolean },
    dispatches: { type: :boolean }
  )

  type :string, optional: true
  def hint
    field.hint.presence
  end

  type :string, optional: true
  def placeholder
    field.placeholder.presence
  end

  type INPUT_UNION
  def input
    field.input
  end

  type "{ value: string; label: string }[]", optional: true
  def choices
    field.choices&.map { |choice| { value: choice.value.to_s, label: choice.label } }
  end

  # Prefilled from what the incident already holds, or from what the responder
  # answered on the render before this one. A multi-select carries a list.
  type "string | string[] | null", optional: true
  def value
    return field.value.map(&:to_s) if field.value.is_a?(Array)

    field.value&.to_s
  end
end
