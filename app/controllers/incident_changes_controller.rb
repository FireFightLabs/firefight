# What changed around an incident, read when its page opens: the resources its catalog entries run on the map, from a
# little before it started until now (ResourceMap::Timeline.for_incident). It reads the map, so the map's read decides.
class IncidentChangesController < InertiaController
  include WhatChangedJson

  authorizes Ability::Action::RESOURCE_MAP, read: %i[show]

  def show
    incident = current_workspace.incidents.find(params[:incident_id])
    subject, from, to = ResourceMap::Timeline.for_incident(current_workspace, current_membership, incident)
    render_what_changed(ResourceMap::Timeline.new(workspace: current_workspace, principal: current_membership, subject: subject, from: from, to: to))
  end
end
