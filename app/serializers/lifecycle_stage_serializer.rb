class LifecycleStageSerializer < BaseSerializer
  object_as :lifecycle_stage

  attributes(
    key: { type: :string },
    name: { type: :string },
    description: { type: :string }
  )

  # Only an open stage can hold the workspace default, since a new incident has
  # to start there. Drives whether the settings screen offers the Default
  # control for the stage at all.
  type :boolean
  def open
    lifecycle_stage.open?
  end
end
