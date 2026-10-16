require "test_helper"

class SandboxProvidersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    ENV.stubs(:[]).with(anything).returns(nil)
    ENV.stubs(:[]).with("SANDBOX_PROVIDER").returns(Integrations::Sandboxes::Boat::KEY)
    ENV.stubs(:[]).with("SANDBOX_BACKUP_PROVIDER").returns(Integrations::Sandboxes::Northflank::KEY)
  end

  test "a workspace follows the deployment's main provider and then its backup" do
    assert_equal [ Integrations::Sandboxes::Boat::KEY, Integrations::Sandboxes::Northflank::KEY ], SandboxProviders.order_for(@workspace)
    assert SandboxProviders.runs_images?(@workspace)
  end

  test "a workspace held to a provider runs only there, never failing over" do
    @workspace.update!(sandbox_provider: Integrations::Sandboxes::Northflank::KEY)

    assert_equal [ Integrations::Sandboxes::Northflank::KEY ], SandboxProviders.order_for(@workspace)
    assert_not SandboxProviders.runs_images?(@workspace)
    assert_includes SandboxProviders.in_use, Integrations::Sandboxes::Northflank::KEY
  end

  test "a workspace can only be held to a provider there is, and blank follows the deployment again" do
    assert_not @workspace.update(sandbox_provider: "fly")

    @workspace.update!(sandbox_provider: " ")
    assert_nil @workspace.reload.sandbox_provider
  end

  test "every provider in the registry has its own box class, and every box class is in the registry" do
    assert_equal SandboxProviders::KEYS.sort, Integrations::Sandboxes.providers.map { |provider_class| provider_class::KEY }.sort
    assert_equal "boat.dev", SandboxProviders.name_of(Integrations::Sandboxes::Boat::KEY)
  end

  test "no provider at all leaves nothing to try" do
    ENV.stubs(:[]).with("SANDBOX_PROVIDER").returns(nil)
    ENV.stubs(:[]).with("SANDBOX_BACKUP_PROVIDER").returns(nil)

    assert_empty SandboxProviders.order_for(@workspace)
  end
end
