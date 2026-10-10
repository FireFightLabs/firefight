# The checks Halon runs on a schedule, created, edited, disabled, enabled, deleted and run now from the Monitoring page.
class InvestigationChecksController < InertiaController
  authorizes Ability::Action::RESOURCE_MONITORING, create: %i[create], update: %i[update disable enable run], delete: %i[destroy]

  include RequiresAgent
  before_action :require_agent!
  before_action :set_check, only: %i[update destroy disable enable run]

  PERMITTED = %i[name kind notes cadence hour weekday time_zone].freeze

  def create
    check = current_workspace.investigation_checks.create!(**check_params, created_by: current_membership)
    redirect_to halon_monitoring_path, notice: "#{check.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: halon_monitoring_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    @check.update!(check_params)
    redirect_to halon_monitoring_path, notice: "#{@check.name} was updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: halon_monitoring_path, inertia: { errors: e.record.errors.to_hash }
  end

  def disable
    @check.disable!
    redirect_to halon_monitoring_path, notice: "#{@check.name} is off."
  end

  def enable
    @check.enable!
    redirect_to halon_monitoring_path, notice: "#{@check.name} is on."
  end

  def run
    blocked = @check.run_now_blocked_reason
    return redirect_to(halon_monitoring_path, alert: blocked) if blocked

    started = InvestigationService.new(current_workspace).start(@check, trigger_source: Investigation::TRIGGER_SCHEDULE, triggered_by: current_membership)
    return redirect_to(halon_monitoring_path, alert: "#{@check.name} #{Investigation::Check::ALREADY_RUNNING}") unless started

    redirect_to halon_monitoring_path, notice: "Halon is running #{@check.name}. It says what it finds when it is done."
  end

  def destroy
    blocked = @check.deletion_blocked_reason
    return redirect_to(halon_monitoring_path, alert: blocked) if blocked

    @check.destroy!
    redirect_to halon_monitoring_path, notice: "#{@check.name} was deleted."
  end

  private

  def set_check
    @check = current_workspace.investigation_checks.with_usage_counts.find(params[:id])
  end

  def check_params
    params.permit(*PERMITTED).to_h.symbolize_keys
  end
end
