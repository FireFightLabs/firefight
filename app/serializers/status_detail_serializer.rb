class StatusDetailSerializer < BaseSerializer
  object_as :status

  attributes(
    name: { type: :string },
    color: { type: :string }
  )

  type :string
  def lifecycle_stage
    status.incident_lifecycle_stage.key
  end
end
