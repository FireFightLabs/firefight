# How Halon has done for this workspace, for every member, since trust in an agent grows from seeing its record.
class HalonPerformanceController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show]

  before_action :require_agent!

  def show
    performance = Investigation::Performance.new(current_workspace, days: params[:days])

    render inertia: "halon/performance", props: {
      performance: HalonPerformanceSerializer.one(performance),
      windows: Investigation::Performance::WINDOWS
    }
  end

  private

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end
end
