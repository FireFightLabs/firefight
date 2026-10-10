# The monitoring and security module's page: the checks Halon runs on a schedule, what it raised on its own, where it
# says it, and whether a security event a provider reports starts it.
class HalonMonitoringController < InertiaController
  authorizes Ability::Action::RESOURCE_MONITORING, read: %i[show], update: %i[update]

  include RequiresAgent
  before_action :require_agent!

  NOTICES_SHOWN = 50

  def show
    checks = current_workspace.investigation_checks.with_usage_counts.ordered
    notices = current_workspace.investigation_notices.includes(:resource, :check).recent.limit(NOTICES_SHOWN)

    render inertia: "halon/monitoring", props: {
      checks: InvestigationCheckSerializer.many(checks),
      notices: InvestigationNoticeSerializer.many(notices),
      monitoringChannel: current_workspace.halon_monitoring_channel,
      securityEventsEnabled: current_workspace.halon_security_events_enabled,
      spend: spend_coverage,
      kinds: Investigation::Check::KIND_DETAILS.values.map { |kind| { value: kind.key, label: kind.label, description: kind.description } },
      cadences: Investigation::Check::CADENCE_LABELS.map { |value, label| { value: value, label: label } }
    }
  end

  def update
    if params.key?(:security_events_enabled)
      enabled = ActiveModel::Type::Boolean.new.cast(params[:security_events_enabled])
      current_workspace.update!(halon_security_events_enabled: enabled)
      return redirect_to halon_monitoring_path, notice: enabled ? "Halon now looks into leaked secrets." : "Halon no longer looks into leaked secrets."
    end

    channel = params[:monitoring_channel].to_s.strip.delete_prefix("#").presence
    current_workspace.update!(halon_monitoring_channel: channel)
    redirect_to halon_monitoring_path, notice: channel ? "Halon now says what it finds in ##{channel}." : "The monitoring channel was cleared."
  end

  private

  # Which connected providers Halon can read spend from, which it cannot, and every one it could.
  def spend_coverage
    coverage = Chat::Skill.coverage(current_workspace, Chat::Skill::SIGNAL_COST)
    name = ->(key) { IntegrationProvider.find(key)&.name || key }
    { read: coverage.read.map(&name).sort, unread: coverage.unread.map(&name).sort,
      offered: Chat::Skill.providers_reading(Chat::Skill::SIGNAL_COST).map(&name).sort }
  end
end
