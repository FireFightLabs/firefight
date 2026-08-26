# The endpoint path is the handle, fixed once the source exists so whatever is
# already posting to it keeps working.
class Api::V1::AlertSourcesController < Api::V1::ApiController
  before_action :set_alert_source, only: %i[update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_READ)

    @alert_sources = current_workspace.alert_sources.order(:name)
  end

  def create
    authorize!(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_CREATE)

    @alert_source = current_workspace.alert_sources.create!(
      name: params.require(:name),
      provider: params.fetch(:provider, AlertSource::PROVIDER_GENERIC)
    )

    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_UPDATE)

    @alert_source.update!({ name: params[:name], enabled: params[:enabled] }.compact)

    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_DELETE)

    @alert_source.destroy!
    head :no_content
  end

  private

  def set_alert_source
    @alert_source = current_workspace.alert_sources.find_by!(endpoint_path: params[:id])
  end
end
