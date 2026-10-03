class StatusCompactSerializer < BaseSerializer
  object_as :status

  attributes(name: { type: :string }, slug: { type: :string }, color: { type: :string })

  type '"triage" | "active" | "closed" | "canceled"'
  def lifecycle_stage
    status.incident_lifecycle_stage.key
  end
end
