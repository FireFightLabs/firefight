# A run's own address, which is what Slack links to. A run is read over the page of what it is about, so this
# sends a run on an incident to that incident with the run open, and shows the run on its own otherwise.
class InvestigationsController < InertiaController
  PROP_INVESTIGATION = "investigation"

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show], create: %i[add_note]

  def show
    investigation = current_workspace.investigations.seen.find(params[:id])
    incident = investigation.incident
    return redirect_to incident_path(incident, Investigation::QUERY_PARAM => investigation.id) if incident

    render inertia: "investigations/investigation", props: {
      PROP_INVESTIGATION => InvestigationDetailSerializer.one(investigation)
    }
  end

  # A responder steering a run while it works. Whoever may start a run may add to one.
  def add_note
    investigation = current_workspace.investigations.seen.find(params[:id])
    text = params[:note].to_s
    blocked = investigation.note_blocked_reason(text)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    investigation.add_note!(text.strip, by: current_membership)
    redirect_back_or_to investigation_path(investigation), notice: Investigation::Noting::NOTE_ADDED
  end
end
