class LifecycleStageSerializer < BaseSerializer
  object_as :lifecycle_stage

  attributes(
    key: { type: :string },
    name: { type: :string },
    description: { type: :string }
  )

  # Only an open stage can hold the default, since a new incident starts there.
  # Decides whether the Default control is offered.
  type :boolean
  def open
    lifecycle_stage.open?
  end
end
