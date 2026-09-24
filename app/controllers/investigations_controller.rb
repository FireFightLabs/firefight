# Every run people can see, and one run in full with its finding, its theories and every step with its receipt.
class InvestigationsController < InertiaController
  PROP_INVESTIGATIONS = "investigations"
  PROP_PAGINATION = "pagination"
  PROP_INVESTIGATION = "investigation"
  PROP_INCIDENT = "incident"
  # Shared with the page through lib/typescript_constants.rb, since a running run's page reloads one prop by name.
  PROPS = {
    "INVESTIGATIONS" => PROP_INVESTIGATIONS, "PAGINATION" => PROP_PAGINATION, "INVESTIGATION" => PROP_INVESTIGATION,
    "INCIDENT" => PROP_INCIDENT
  }.freeze

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[index show]

  before_action :require_agent!

  # Every run, or one incident's runs when its header has several to show.
  def index
    incident = current_workspace.incidents.find(params[:incident_id]) if params[:incident_id].present?
    scope = incident ? current_workspace.investigations.where(subject: incident) : current_workspace.investigations
    listed = scope.page_of(page: params[:page], per_page: params[:per_page])
    render inertia: "investigations/index", props: {
      PROP_INVESTIGATIONS => InvestigationListItemSerializer.many(listed[:investigations]),
      PROP_PAGINATION => listed[:pagination],
      PROP_INCIDENT => incident && { id: incident.id, identifier: incident.identifier, name: incident.name }
    }
  end

  def show
    investigation = current_workspace.investigations.seen.find(params[:id])
    render inertia: "investigations/investigation", props: {
      PROP_INVESTIGATION => InvestigationDetailSerializer.one(investigation)
    }
  end

  private

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
