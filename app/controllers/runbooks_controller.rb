class RunbooksController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_runbook, only: [ :update, :destroy ]

  def create
    runbook = current_workspace.runbooks.new(
      name: params[:name],
      summary: params[:summary],
      content: params[:content],
      external_url: params[:external_url]
    )

    Runbook.transaction do
      runbook.save!
      runbook.sync_steps!(step_params) if params.key?(:steps)
      runbook.sync_conditions!(condition_params) if params.key?(:conditions)
    end

    redirect_to settings_runbooks_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_runbooks_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    attrs = {
      name: params[:name],
      summary: params[:summary],
      content: params[:content],
      external_url: params[:external_url]
    }.compact

    Runbook.transaction do
      @runbook.update!(attrs)
      @runbook.sync_steps!(step_params) if params.key?(:steps)
      @runbook.sync_conditions!(condition_params) if params.key?(:conditions)
    end

    redirect_to settings_runbooks_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_runbooks_path, inertia: { errors: e.record.errors.to_hash }
  end

  def destroy
    @runbook.update!(deleted_at: Time.current)
    redirect_to settings_runbooks_path
  end

  private

  def set_runbook
    @runbook = current_workspace.runbooks.active.find(params[:id])
  end

  def step_params
    Array(params[:steps])
      .select { |s| s.is_a?(ActionController::Parameters) }
      .reject { |s| ActiveModel::Type::Boolean.new.cast(s[:_destroy]) }
      .map { |s| { title: s[:title], instruction: s[:instruction] } }
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
