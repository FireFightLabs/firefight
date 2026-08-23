class RunbooksController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_runbook, only: [ :update, :destroy, :disable, :enable ]

  def create
    runbook = current_workspace.runbooks.new(
      name: params[:name],
      summary: params[:summary],
      content: params[:content],
      external_url: params[:external_url],
      always_attach: params[:always_attach] || false
    )

    Runbook.transaction do
      runbook.save!
      runbook.sync_steps!(step_params) if params.key?(:steps)
      runbook.sync_conditions!(condition_params) if params.key?(:conditions)
    end

    redirect_to settings_runbooks_path, notice: "#{runbook.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_runbooks_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    attrs = {
      name: params[:name],
      summary: params[:summary],
      content: params[:content],
      external_url: params[:external_url],
      always_attach: params[:always_attach]
    }.compact

    Runbook.transaction do
      @runbook.update!(attrs)
      @runbook.sync_steps!(step_params) if params.key?(:steps)
      @runbook.sync_conditions!(condition_params) if params.key?(:conditions)
    end

    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_runbooks_path, inertia: { errors: e.record.errors.to_hash }
  end

  def disable
    @runbook.update!(deleted_at: Time.current)
    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was disabled."
  end

  def enable
    @runbook.update!(deleted_at: nil)
    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was enabled."
  end

  # Deletes only when nothing references it. Previously this always soft-deleted
  # with no enable control anywhere, so a "deleted" runbook was unreachable but
  # still holding its slug.
  def destroy
    if @runbook.deletion_blocked_reason
      return redirect_to settings_runbooks_path, alert: @runbook.deletion_blocked_reason
    end

    @runbook.destroy!
    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was deleted."
  end

  def reorder
    Runbook.reorder!(current_workspace, params.require(:ordered_ids))
    redirect_to settings_runbooks_path, notice: "Runbook order updated."
  end

  private

  def set_runbook
    @runbook = current_workspace.runbooks.find(params[:id])
  end

  def step_params
    Array(params[:steps])
      .select { |s| s.is_a?(ActionController::Parameters) }
      .map { |s| { id: s[:id], title: s[:title], instruction: s[:instruction] } }
  end

  def condition_params
    Array(params[:conditions])
      .select { |c| c.is_a?(ActionController::Parameters) }
      .map do |c|
        {
          condition_field: c[:condition_field],
          operator: c[:operator],
          values: Array(c[:values]),
          incident_field_definition_id: c[:incident_field_definition_id]
        }
      end
  end
end
