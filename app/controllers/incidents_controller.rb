class IncidentsController < InertiaController
  before_action :require_authentication

  def show
    render inertia: "incidents/show"
  end

  def postmortem
    render inertia: "incidents/postmortem"
  end
end
