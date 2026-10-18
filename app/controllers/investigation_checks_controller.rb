# The checks Halon runs on a schedule, created, edited, disabled, enabled, deleted and run now from the Monitoring page.
class InvestigationChecksController < InertiaController
  authorizes Ability::Action::RESOURCE_MONITORING, create: %i[create], update: %i[update disable enable run take_over change_owner], delete: %i[destroy]

  include RequiresAgent
  before_action :require_agent!
  before_action :set_check, only: %i[update destroy disable enable run take_over change_owner]
  # Who a check runs as decides what it reads, so only an admin hands it to someone.
  before_action :require_admin_to_hand_over!, only: %i[take_over change_owner]

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

  def take_over = hand_to(current_membership)

  # Read with removed members too, so giving it to one who left says so rather than that nobody was chosen.
  def change_owner = hand_to(WorkspaceMembership.find_by(workspace_id: current_workspace.id, id: params[:owner_id]))

  def destroy
    blocked = @check.deletion_blocked_reason
    return redirect_to(halon_monitoring_path, alert: blocked) if blocked

    @check.destroy!
    redirect_to halon_monitoring_path, notice: "#{@check.name} was deleted."
  end

  private

  def require_admin_to_hand_over!
    authorize_web!(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE)
  end

  def hand_to(member)
    blocked = @check.hand_to_blocked_reason(member)
    return redirect_to(halon_monitoring_path, alert: blocked) if blocked

    resumed = @check.paused?
    @check.hand_to!(member)
    redirect_to halon_monitoring_path, notice: "#{@check.name} is now owned by #{member.display_name}#{' and runs again' if resumed}."
  end

  def set_check
    @check = current_workspace.investigation_checks.with_usage_counts.find(params[:id])
  end

  def check_params
    params.permit(*PERMITTED).to_h.symbolize_keys
  end
end
