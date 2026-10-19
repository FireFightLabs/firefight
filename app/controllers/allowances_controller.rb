# What Halon may do without asking in any chat, under Settings, Workspace. Part of who may do what, so the admins who
# hand out abilities and approval rules decide it too, as they decide unattended rules.
class AllowancesController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: :update, delete: :destroy
  before_action :set_allowance, only: [ :update, :destroy ]

  def create
    allowance = current_workspace.allowances.create!(allowance_attributes.merge(created_by: current_membership))
    redirect_to settings_workspace_path, notice: "#{quoted(allowance)} was added to what Halon may do without asking."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_workspace_path, inertia: { errors: e.record.errors.to_hash(true).transform_values { |messages| messages.join(" ") } }
  end

  # The switch on a row sends only enabled, the dialog the whole entry.
  def update
    if @allowance.update(allowance_attributes)
      redirect_to settings_workspace_path, notice: updated_notice
    else
      redirect_back fallback_location: settings_workspace_path, inertia: { errors: @allowance.errors.to_hash(true).transform_values { |messages| messages.join(" ") } }
    end
  end

  def destroy
    blocked = @allowance.delete_blocked_reason
    return redirect_to settings_workspace_path, alert: blocked if blocked

    @allowance.destroy!
    redirect_to settings_workspace_path, notice: "#{quoted(@allowance)} was deleted."
  end

  private

  def set_allowance
    @allowance = current_workspace.allowances.find(params[:id])
  end

  def quoted(allowance) = "\"#{allowance.sentence}\""

  def updated_notice
    return "#{quoted(@allowance)} was updated." unless @allowance.saved_change_to_enabled? && @allowance.saved_changes.keys.excluding("enabled", "updated_at").empty?

    "#{quoted(@allowance)} is #{@allowance.enabled? ? 'on' : 'off'}."
  end

  def allowance_attributes
    Ability::Allowance.changes_from(current_workspace, params.require(:allowance).permit(:capability, :action_key, :integration, :environment, :enabled))
  end
end
