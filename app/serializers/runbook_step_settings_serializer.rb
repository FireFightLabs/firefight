class RunbookStepSettingsSerializer < BaseSerializer
  object_as :step

  type :string
  def id
    step.id
  end

  attributes(
    title: { type: :string },
    instruction: { type: :string, optional: true },
    position: { type: :number }
  )
end
