# How Halon works when nobody is watching: whether an alert starts it, what those runs may spend in an hour, whether it
# pages whoever is on call, and the changes a team lets it make on its own (UnattendedRulesController).
class HalonOnCallController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  SETTINGS = %i[alert_investigations_enabled alert_storm_ceiling_cents on_call_paging_enabled].freeze

  def show
    render inertia: "halon/on-call", props: {
      settings: OnCallSettingsSerializer.one(current_workspace),
      rules: UnattendedRuleSerializer.many(current_workspace.unattended_rules.with_usage_counts.includes(:resource, :created_by).order(:created_at)),
      resources: UnattendedRuleResourceSerializer.many(Ability::UnattendedRule.resource_choices(current_workspace)),
      investigator: SystemAgent.investigator.actor_display_name
    }
  end

  def update
    current_workspace.update_settings!(params.permit(*SETTINGS))
    redirect_to halon_on_call_path, notice: "On-call settings were updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to halon_on_call_path, inertia: { errors: e.record.errors.to_hash }
  end
end
