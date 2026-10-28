# Connecting one of the workspace's AI subscriptions, or signing one in again, on the AI accounts card. The sign-in
# happens at the provider through the subscription proxy. The page shows its code or asks for the address it landed on,
# and asks every few seconds whether it finished.
class SubscriptionSignInsController < InertiaController
  # The address a browser sign-in lands on carries the provider's one-time code, which is filtered from the logs.
  CALLBACK_ADDRESS_PARAM = :callback_address

  authorizes Ability::Action::RESOURCE_AI_ACCOUNTS, create: %i[create finish advance destroy]

  before_action :set_sign_in, only: %i[finish advance destroy]

  def create
    account = current_workspace.workspace_ai_accounts.subscriptions.find(params[:account_id]) if params[:account_id].present?
    account ? service.start_again!(account) : service.start!(params[:subscription].to_s, site: params[:site].presence)
    back
  rescue SubscriptionProxy::SignIns::Failed => e
    back alert: e.message
  end

  def finish
    settled(service.hand_back!(@sign_in, params[CALLBACK_ADDRESS_PARAM].to_s))
  rescue SubscriptionProxy::SignIns::Failed, SubscriptionProxy::SignIns::StillWaiting => e
    back alert: e.message
  end

  def advance
    settled(service.advance!(@sign_in))
  rescue SubscriptionProxy::SignIns::Failed, SubscriptionProxy::SignIns::StillWaiting => e
    back alert: e.message
  end

  def destroy
    # One that finished first was connected, which its own answer said.
    return back unless service.cancel!(@sign_in)

    back notice: "#{@sign_in.subscription_definition&.name || 'The'} sign-in was cancelled."
  end

  private

  def service = SubscriptionProxy::SignIns.new(current_workspace, by: current_membership)

  # A person sees only their own sign-ins.
  def set_sign_in
    @sign_in = SubscriptionSignIn.find_by!(id: params[:id], workspace: current_workspace, started_by: current_membership)
  end

  def back(**flash) = redirect_back(fallback_location: settings_workspace_path, **flash)

  def settled(outcome)
    return back unless outcome&.fresh

    named = outcome.account.subscription_named
    done = outcome.reconnected ? "#{named} signed in again." : "#{named} connected."
    result = WorkspaceAiAccountService.new(current_workspace, by: current_membership).check!(outcome.account)
    return back notice: done if result.checked?

    back alert: "#{done.delete_suffix('.')}, but the check failed. #{result.error}"
  end
end
