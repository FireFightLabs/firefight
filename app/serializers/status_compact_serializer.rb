class StatusCompactSerializer < BaseSerializer
  object_as :status

  attributes(name: { type: :string })

  type :string
  def lifecycle_stage
    status.incident_lifecycle_stage.key
  end
end
