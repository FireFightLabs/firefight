class DashboardController < InertiaController
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
      severityOptions: SeverityOptionSerializer.many(current_workspace.incident_severities.order(:position)),
      onboarding: onboarding_props
    }
  end

  private

  # The first-run dialog is the installer's, once. The channel link is built by the platform.
  def onboarding_props
    onboarding = current_workspace.onboarding
    {
      dialogPending: onboarding.present? && onboarding.dialog_pending_for?(current_membership),
      steps: WorkspaceOnboarding::STEPS,
      incidentsChannelUrl: WorkspaceAdapter.for(current_workspace).channel_url(channel_id: current_workspace.incidents_channel_id)
    }
  end

  def severity_slugs
    @severity_slugs ||= Array(params[:severities]).compact_blank
  end

  # The UI offers only Active and Closed, so active includes triage.
  def lifecycle_keys
    @lifecycle_keys ||= Array(params[:statuses]).compact_blank.flat_map { |k|
      k == IncidentLifecycleStage::ACTIVE ? [ IncidentLifecycleStage::TRIAGE, IncidentLifecycleStage::ACTIVE ] : k
    }
  end
end
