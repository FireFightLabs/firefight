# Outbound webhooks over REST, matching upsert_webhook and delete_webhook on
# MCP. The signing secret never leaves through here: it is read on demand from
# the dashboard, so it is not sitting in every listing waiting to be scraped.
class Api::V1::WebhooksController < Api::V1::ApiController
  before_action :set_webhook, only: %i[update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_READ)

    @webhooks = current_workspace.webhooks.ordered
  end

  def create
    authorize!(Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_CREATE)

    @webhook = current_workspace.webhooks.create!(
      name: params.require(:name),
      url: params.require(:url),
      subscribed_events: params[:subscribed_events] || []
    )

    render :show, status: :created
  end

  # Sending subscribed_events replaces the set rather than adding to it.
  def update
    authorize!(Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_UPDATE)

    @webhook.update!({
      name: params[:name], url: params[:url], subscribed_events: params[:subscribed_events]
    }.compact)
    toggle! unless params[:enabled].nil?

    @webhook.reload
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_DELETE)

    @webhook.destroy!
    head :no_content
  end

  private

  def toggle!
    ActiveModel::Type::Boolean.new.cast(params[:enabled]) ? @webhook.activate! : @webhook.deactivate!
  end

  def set_webhook
    @webhook = current_workspace.webhooks.find(params[:id])
  end
end
