class IncidentSeveritiesController < InertiaController
  include ActionView::Helpers::TextHelper

  before_action :require_authentication
  before_action :require_admin!
  before_action :set_severity, only: [ :update, :disable, :enable, :destroy ]

  def create
    name = params[:name].to_s.strip
    severity = current_workspace.incident_severities.new(
      name: name,
      slug: name.parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280",
      rank: 1
    )

    # Appended last, so least severe. renumber! then derives every rank from
    # the resulting order rather than trusting the placeholder above.
    severity.save_in_position!
    renumber!
    redirect_to settings_severities_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_severities_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    if @severity.update(name: params[:name], description: params[:description], color: params[:color])
      redirect_to settings_severities_path
    else
      redirect_back fallback_location: settings_severities_path, inertia: { errors: @severity.errors.to_hash }
    end
  end

  def disable
    @severity.update!(deleted_at: Time.current)
    redirect_to settings_severities_path
  end

  def enable
    @severity.update!(deleted_at: nil)
    redirect_to settings_severities_path
  end

  def destroy
    if @severity.is_default?
      return redirect_to settings_severities_path,
        alert: "#{@severity.name} is the default severity. Make another severity the default before deleting it."
    end

    count = @severity.incident_count
    if count.positive?
      return redirect_to settings_severities_path,
        alert: "#{@severity.name} is in use by #{pluralize(count, 'incident')} and cannot be deleted. Disable it instead."
    end

    @severity.destroy!
    renumber!
    redirect_to settings_severities_path, notice: "#{@severity.name} was deleted."
  end

  def reorder
    IncidentSeverity.reorder!(current_workspace, params.require(:ordered_ids))
    redirect_to settings_severities_path
  end

  private

  # Closes the gaps a create or destroy leaves behind and re-derives every rank.
  def renumber!
    IncidentSeverity.reorder!(current_workspace, current_workspace.incident_severities.ordered.pluck(:id))
  end

  def set_severity
    @severity = current_workspace.incident_severities.find(params[:id])
  end
end
