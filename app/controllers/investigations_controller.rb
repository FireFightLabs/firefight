# A run's own address, which is what Slack links to. A run is read over the page of what it is about, so this
# sends a run on an incident to that incident with the run open, and shows the run on its own otherwise.
class InvestigationsController < InertiaController
  PROP_INVESTIGATION = "investigation"

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show]

  def show
    investigation = current_workspace.investigations.seen.find(params[:id])
    incident = investigation.incident
    return redirect_to incident_path(incident, Investigation::QUERY_PARAM => investigation.id) if incident

    render inertia: "investigations/investigation", props: {
      PROP_INVESTIGATION => InvestigationDetailSerializer.one(investigation)
    }
  end
end
