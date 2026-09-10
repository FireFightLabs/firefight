# What a responder is asked right now, choices included. The settings serializer
# describes how a field is configured.
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

  # Prefilled from the incident or the responder's previous answer. A multi-select carries a list.
  type "string | string[] | null", optional: true
  def value
    return field.value.map(&:to_s) if field.value.is_a?(Array)

    field.value&.to_s
  end
end
