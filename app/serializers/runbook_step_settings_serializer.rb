class RunbookStepSettingsSerializer < BaseSerializer
  object_as :step

  type :string
  def id
    step.id
  end

  attributes(
    title: { type: :string },
    instruction: { type: :string, optional: true },
    position: { type: :number },
    tool: { type: :string, optional: true }
  )

  # The tool's arguments, whose values may name an input as {{key}}.
  type "Record<string, unknown>"
  def arguments
    step.arguments
  end
end
