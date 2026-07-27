class IncidentStatusesController < InertiaController
  include ActionView::Helpers::TextHelper

  before_action :require_authentication
  before_action :require_admin!
  before_action :set_status, only: [ :update, :disable, :enable, :destroy, :make_default ]

  def create
    lifecycle_stage = IncidentLifecycleStage.find_by!(key: params.require(:lifecycle_stage_key))
    name = params[:name].to_s.strip

    status = current_workspace.incident_statuses.new(
      incident_lifecycle_stage: lifecycle_stage,
      name: name,
      slug: name.parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280"
    )

    status.save_in_position!
    redirect_to settings_statuses_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_statuses_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    if @status.update(name: params[:name], description: params[:description], color: params[:color])
      redirect_to settings_statuses_path
    else
      redirect_back fallback_location: settings_statuses_path, inertia: { errors: @status.errors.to_hash }
    end
  end

  def disable
    if @status.is_default?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is the default status and has to stay enabled. Make another status the default first."
    end

    if @status.last_enabled_in_stage?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is the only enabled status in #{stage_name(@status)}. Add another one before disabling it."
    end

    @status.update!(deleted_at: Time.current)
    redirect_to settings_statuses_path, notice: "#{@status.name} was disabled."
  end

  def enable
    @status.update!(deleted_at: nil)
    redirect_to settings_statuses_path, notice: "#{@status.name} was enabled."
  end

  def make_default
    unless @status.enabled?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is disabled. Enable it before making it the default."
    end

    unless @status.live?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is a #{stage_name(@status)} status. A new incident has to start in triage or active."
    end

    @status.make_default!
    redirect_to settings_statuses_path, notice: "#{@status.name} is now the default status."
  end

  def destroy
    if @status.is_default?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is the default status. Make another status the default before deleting it."
    end

    count = @status.incident_count
    if count.positive?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is in use by #{pluralize(count, 'incident')} and cannot be deleted. Disable it instead."
    end

    if @status.last_enabled_in_stage?
      return redirect_to settings_statuses_path,
        alert: "#{@status.name} is the only enabled status in #{stage_name(@status)}. Add another one before deleting it."
    end

    @status.destroy!
    renumber!
    redirect_to settings_statuses_path, notice: "#{@status.name} was deleted."
  end

  def reorder
    IncidentStatus.reorder_within_stage!(
      current_workspace,
      params.require(:lifecycle_stage_key),
      params.require(:ordered_ids)
    )
    redirect_to settings_statuses_path, notice: "Status order updated."
  end

  private

  def renumber!
    IncidentStatus.reorder!(current_workspace, current_workspace.incident_statuses.ordered.pluck(:id))
  end

  def stage_name(status)
    status.incident_lifecycle_stage.name
  end

  def set_status
    @status = current_workspace.incident_statuses.find(params[:id])
  end
end
