class LifecycleStageSerializer < BaseSerializer
  attributes(
    key: { type: :string },
    name: { type: :string },
    description: { type: :string }
  )
end
