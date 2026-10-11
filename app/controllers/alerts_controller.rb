class AlertsController < InertiaController
  authorizes Ability::Action::RESOURCE_ALERTS, update: :resolve

  # For a tool that never says an alert cleared. The gateway records who resolved it in the activity log.
  def resolve
    alert = current_workspace.alerts.find(params[:id])
    if (reason = alert.resolve_blocked_reason)
      return redirect_back fallback_location: settings_alerts_path, alert: reason
    end

    AlertIngestService.new(alert.alert_source).resolve(alert)
    redirect_back fallback_location: settings_alerts_path, notice: "#{alert.title} was resolved."
  end
end
