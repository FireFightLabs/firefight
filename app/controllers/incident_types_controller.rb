class IncidentTypesController < InertiaController
  include ActionView::Helpers::TextHelper

  before_action :require_authentication
  before_action :require_admin!
  before_action :set_incident_type, only: [ :update, :destroy, :disable, :enable, :make_default ]

  def create
    name = params[:name].to_s.strip
    incident_type = current_workspace.incident_types.new(
      name: name,
      slug: name.parameterize(separator: "_"),
      description: params[:description],
      color: params[:color]
    )

    incident_type.save_in_position!
    incident_type.make_default! if ActiveModel::Type::Boolean.new.cast(params[:is_default])
    redirect_to settings_types_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_types_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    attrs = {
      name: params[:name],
      description: params[:description],
      color: params[:color]
    }.compact

    if @incident_type.update(attrs)
      @incident_type.make_default! if ActiveModel::Type::Boolean.new.cast(params[:is_default])
      redirect_to settings_types_path
    else
      redirect_back fallback_location: settings_types_path, inertia: { errors: @incident_type.errors.to_hash }
    end
  end

  def disable
    if @incident_type.is_default?
      return redirect_to settings_types_path,
        alert: "#{@incident_type.name} is the default type and has to stay enabled. Make another type the default first."
    end

    @incident_type.update!(deleted_at: Time.current)
    redirect_to settings_types_path, notice: "#{@incident_type.name} was disabled."
  end

  def enable
    @incident_type.update!(deleted_at: nil)
    redirect_to settings_types_path, notice: "#{@incident_type.name} was enabled."
  end

  def make_default
    unless @incident_type.enabled?
      return redirect_to settings_types_path,
        alert: "#{@incident_type.name} is disabled. Enable it before making it the default."
    end

    @incident_type.make_default!
    redirect_to settings_types_path, notice: "#{@incident_type.name} is now the default type."
  end

  # Deletes only when nothing references the type. Previously this always
  # soft-deleted, which left no way back: the settings screen had no enable
  # control, so a "deleted" type was simply gone but still in the table.
  def destroy
    if @incident_type.is_default?
      return redirect_to settings_types_path,
        alert: "#{@incident_type.name} is the default type. Make another type the default before deleting it."
    end

    count = @incident_type.incident_count
    if count.positive?
      return redirect_to settings_types_path,
        alert: "#{@incident_type.name} is in use by #{pluralize(count, 'incident')} and cannot be deleted. Disable it instead."
    end

    @incident_type.destroy!
    renumber!
    redirect_to settings_types_path, notice: "#{@incident_type.name} was deleted."
  end

  def reorder
    IncidentType.reorder!(current_workspace, params.require(:ordered_ids))
    redirect_to settings_types_path, notice: "Type order updated."
  end

  private

  def renumber!
    IncidentType.reorder!(current_workspace, current_workspace.incident_types.ordered.pluck(:id))
  end

  def set_incident_type
    @incident_type = current_workspace.incident_types.find(params[:id])
  end
end
