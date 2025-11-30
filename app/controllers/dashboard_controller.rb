class DashboardController < InertiaController
  before_action :require_authentication

  def index
    render inertia: "dashboard/index"
  end
end
