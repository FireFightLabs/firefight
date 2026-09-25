module Operator
  # Every incident across workspaces, and one incident's whole process on one timeline.
  class IncidentsController < BaseController
    PER_PAGE = 25

    def index
      scope = Incident.includes(:workspace, :incident_status).order(declared_at: :desc, id: :desc)
      page = [ params[:page].to_i, 1 ].max
      incidents = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      more = incidents.size > PER_PAGE
      incidents = incidents.first(PER_PAGE)
      problems = IncidentProcess.problem_counts(incidents)

      render inertia: "operator/incidents/index", props: {
        incidents: OperatorIncidentRowSerializer.many(incidents.map { |incident| IncidentProcess::Row.new(incident, problems[incident.id]) }),
        page: page, more: more
      }
    end

    def show
      incident = Incident.includes(:workspace, :incident_status, :incident_severity).find(params[:id])
      process = IncidentProcess.new(incident)

      render inertia: "operator/incidents/show", props: {
        incident: OperatorIncidentRowSerializer.one(IncidentProcess::Row.new(incident, process.counts[:problems])),
        entries: process.entries.map { |entry| OperatorProcessEntrySerializer.one(entry) }
      }
    end
  end
end
