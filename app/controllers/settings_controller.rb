class SettingsController < InertiaController
  before_action :require_authentication

  def index
    render inertia: "settings/index"
  end
end
