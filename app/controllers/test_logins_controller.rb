# The test accounts Halon's browser signs in with, one per site. Each is a connection's credential, so only admins manage
# them, and the password is taken here and never sent back.
class TestLoginsController < InertiaController
  authorizes Ability::Action::RESOURCE_INTEGRATIONS,
    read: :index,
    create: :create,
    update: :update,
    delete: :destroy

  include RequiresAgent
  before_action :require_agent!
  before_action :set_login, only: %i[update destroy]

  FIELDS = %i[name site_url login_url username password].freeze

  def index
    render inertia: "settings/test-logins", props: {
      testLogins: TestLoginSerializer.many(Integrations::SiteLogins.listed(current_workspace))
    }
  end

  def create
    login = Integration::SiteLogin.new(workspace: current_workspace, **login_params).save!
    redirect_to settings_test_logins_path, notice: "Test login for #{login.host} was added."
  rescue ActiveModel::ValidationError => error
    refused(error.model)
  end

  def update
    @login.assign_attributes(login_params)
    @login.save!
    redirect_to settings_test_logins_path, notice: "Test login for #{@login.host} was updated."
  rescue ActiveModel::ValidationError => error
    refused(error.model)
  end

  def destroy
    @login.destroy!
    redirect_to settings_test_logins_path, notice: "Test login for #{@login.host} was deleted. Halon no longer signs in there."
  end

  private

  def set_login
    @login = Integration::SiteLogin.find_in!(current_workspace, params[:id])
  end

  def login_params = params.permit(*FIELDS).to_h.symbolize_keys

  def refused(login)
    redirect_to settings_test_logins_path, inertia: { errors: login.errors.to_hash.transform_values(&:first) }
  end
end
