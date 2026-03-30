class DashboardController < InertiaController
  before_action :require_authentication

  def index
    result = current_workspace.incidents.filtered_list(
      filters: { search: params[:search], severities: severity_slugs, lifecycle_stages: lifecycle_keys },
      page: params[:page],
      per_page: params[:per_page]
    )

    render inertia: "dashboard/index", props: {
      incidents: IncidentListItemSerializer.many(result[:incidents]),
      stats: InertiaRails.defer { DashboardStats.new(current_workspace).to_a },
      pagination: result[:pagination],
      filters: {
        search: params[:search].to_s,
        severities: severity_slugs,
        statuses: Array(params[:statuses]).compact_blank
      },
      severityOptions: SeverityOptionSerializer.many(current_workspace.incident_severities.order(:position))
    }
  end

  private

  def severity_slugs
    @severity_slugs ||= Array(params[:severities]).compact_blank
  end

  def lifecycle_keys
    @lifecycle_keys ||= Array(params[:statuses]).compact_blank.flat_map { |k|
      k == IncidentLifecycleStage::ACTIVE ? [ IncidentLifecycleStage::TRIAGE, IncidentLifecycleStage::ACTIVE ] : k
    }
  end
end
