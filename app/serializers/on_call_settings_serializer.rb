class OnCallSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(
    alert_investigations_enabled: { type: :boolean },
    alert_storm_ceiling_cents: { type: :number },
    on_call_paging_enabled: { type: :boolean }
  )

  # What runs alerts started in the last hour hold of the ceiling now.
  type :number
  def storm_committed_cents = workspace.storm_committed_cents
end
