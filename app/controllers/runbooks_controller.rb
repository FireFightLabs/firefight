class RunbooksController < InertiaController
  include FreeFormParams

  authorizes Ability::Action::RESOURCE_RUNBOOKS, create: :create, update: %i[update disable enable reorder], delete: :destroy
  before_action :set_runbook, only: [ :update, :destroy, :disable, :enable ]

  def create
    runbook = current_workspace.runbooks.new(
      name: params[:name],
      summary: params[:summary],
      content: params[:content],
      external_url: params[:external_url],
      always_attach: params[:always_attach] || false,
      **procedure_params
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
    }.compact.merge(procedure_params)

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
    @runbook.disable!
    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was disabled."
  end

  def enable
    @runbook.enable!
    redirect_to settings_runbooks_path, notice: "#{@runbook.name} was enabled."
  end

  # Deletes only when unreferenced. Soft deleting with no enable control left a runbook
  # unreachable but still holding its slug.
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
      .map { |s| { id: s[:id], title: s[:title], instruction: s[:instruction], tool: s[:tool].presence, arguments: object_param(s[:arguments]) || {} } }
  end

  # What makes a runbook one Halon can run, each touched only when the form sends it.
  def procedure_params
    {
      inputs: (Array(params[:inputs]).select { |input| input.is_a?(ActionController::Parameters) }.map { |input| input.permit(:key, :question, :default).to_h } if params.key?(:inputs)),
      aliases: (Array(params[:aliases]).map(&:to_s) if params.key?(:aliases)),
      watch: (object_param(params[:watch]) if params.key?(:watch))
    }.compact.tap { |given| given[:watch] = nil if params.key?(:watch) && params[:watch].blank? }
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
