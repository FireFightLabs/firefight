# A dry run of alert routing against hypothetical alert fields. Nothing is
# created and nobody is notified, so this is the safe way to ask what a rule
# change would do before making it.
class Api::V1::RoutingController < Api::V1::ApiController
  def evaluate
    authorize!(Ability::Action::RESOURCE_POLICIES, Ability::Action::ACTION_READ)

    @routed = Alert::Router.new(current_workspace, scope).route(raw_fields)
    unless @routed
      return render json: error_response("validation_error", "No enabled alert routing policy configured for this scope."),
                    status: :unprocessable_entity
    end

    @role_warnings = Alert::RoutingRoleGaps.for(current_workspace)
    render :evaluate
  end

  private

  def raw_fields
    (params[:fields] || {}).to_unsafe_h.transform_keys(&:to_s).transform_values(&:to_s)
  end

  def scope
    return current_workspace if params[:source].blank?

    current_workspace.alert_sources.find_by!(name: params[:source])
  end
end
