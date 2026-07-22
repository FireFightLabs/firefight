class RunbookSettingsSerializer < BaseSerializer
  object_as :runbook

  type :string
  def id
    runbook.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    summary: { type: :string, optional: true },
    content: { type: :string, optional: true },
    external_url: { type: :string, optional: true },
    position: { type: :number }
  )

  has_many :runbook_steps, as: :steps, serializer: RunbookStepSettingsSerializer

  type "IncidentConditionSettings[]", optional: true
  def conditions
    runbook.incident_conditions.map do |c|
      { id: c.id, conditionField: c.condition_field, operator: c.operator, values: c.values }
    end
  end
end
