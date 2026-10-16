require "test_helper"

# A hosted build hears of each new workspace once, inside the transaction that creates it, which is where it gives
# starter credits. A workspace already there, installed again, is never new.
class Workspace::CreatedTest < ActiveSupport::TestCase
  include AiAccountTestHelper

  setup do
    @backend = on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, false))
  end

  test "a workspace signed up from the dashboard is told once, inside the transaction that creates it" do
    outside = ActiveRecord::Base.connection.open_transactions
    during = []
    @backend.define_singleton_method(:workspace_created!) do |workspace|
      during << ActiveRecord::Base.connection.open_transactions
      (self.created ||= []) << workspace.id
    end

    membership = Workspace.sign_up!(name: "Starter Co", user: new_user)

    assert_equal [ membership.workspace_id ], @backend.created
    assert_equal [ outside + 1 ], during
  end

  test "a sign up that fails after being told is undone with it, and trying again tells once for the workspace made" do
    user = new_user
    SignupNotificationService.stubs(:announce).raises(ActiveRecord::StatementInvalid, "lost the connection").then.returns(nil)

    assert_raises(ActiveRecord::StatementInvalid) { WorkspaceSignupService.new.create(name: "Retry Co", user: user) }
    assert_equal 1, @backend.created.size
    assert_not Workspace.exists?(@backend.created.first)

    membership = WorkspaceSignupService.new.create(name: "Retry Co", user: user)

    assert_equal [ membership.workspace_id ], @backend.created.select { |id| Workspace.exists?(id) }
  end

  test "a Slack install that creates the workspace tells once, and installing into it again tells nothing" do
    team_id = "T#{SecureRandom.hex(8)}"
    first = install_slack(slack_auth_hash(team_id))
    install_slack(slack_auth_hash(team_id, uid: "U_SECOND", info: { name: "Second", email: "second-#{SecureRandom.hex(3)}@example.com" }))

    assert_equal [ first[:workspace].id ], @backend.created
  end

  test "an install someone runs themselves gives nothing and still creates the workspace" do
    Entitlements.reset_backend!

    membership = Workspace.sign_up!(name: "Self Hosted Co", user: new_user)

    assert membership.workspace.persisted?
    assert_nil Entitlements.ai_credit(membership.workspace)
    assert_nil @backend.created
  end

  private

  def install_slack(auth_hash)
    Workspace.process_chat_installation(install: SlackAuthenticationService.install_from(auth_hash),
                                        installer: SlackAuthenticationService.installer_from(auth_hash))
  end

  def new_user = User.create!(email: "starter-#{SecureRandom.hex(4)}@example.com", name: "Sam Starter")

  def slack_auth_hash(team_id, overrides = {})
    mock_slack_auth_hash(overrides.merge(extra: { team_info: { "id" => team_id, "name" => "Starter Team" } }))
  end
end
