require "test_helper"

module Integrations
  class ConnectionRefreshTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "a connection that is made or refreshed is put on the resource map at once, not at the next hourly sweep" do
      integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake Native")
      row = integration.integration_environments.create!
      NativePack.stubs(:for).with("fake").returns(FakeNativePack)

      assert ConnectionRefresh.run!(integration)

      assert_enqueued_with(job: MapSweepJob, args: [ row ])
    end
  end
end
