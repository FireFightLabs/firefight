class IncidentStatusesController < InertiaController
  include ManagesConfigurableOptions

  manages_options_as Ability::Action::RESOURCE_STATUSES

  # Statuses share one position sequence across stages, so a drag inside a stage
  # renumbers the workspace with the other stages held put.
  def reorder
    IncidentStatus.reorder_within_stage!(
      current_workspace,
      params.require(:lifecycle_stage_key),
      params.require(:ordered_ids)
    )
    redirect_to options_path, notice: "Status order updated."
  end

  private

  def option_model
    IncidentStatus
  end

  def options_path
    settings_statuses_path
  end

  def create_attributes
    { incident_lifecycle_stage: IncidentLifecycleStage.find_by!(key: params.require(:lifecycle_stage_key)) }
  end
end
