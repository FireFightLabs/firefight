require "test_helper"

module Integrations
  class MapSweepJobTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "one connection's unexpected error is recorded on it and the hourly sweep goes on to the others" do
      broken = connection("northflank")
      working = connection("render")
      MapSweep.stubs(:due?).returns(true)
      MapSweep.stubs(:run!).with { |row| row.id == broken.id }.raises(TypeError, "no implicit conversion of Hash into Array")
      MapSweep.expects(:run!).with { |row| row.id == working.id }.returns(true)
      IntegrationEnvironment.where.not(id: [ broken.id, working.id ]).update_all(enabled: false)

      MapSweepJob.perform_now

      assert_equal MapSweep::UNEXPECTED, broken.reload.map_error
      assert_nil working.reload.map_error
    end

    private

    def connection(provider)
      @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: provider.humanize, slug: provider)
                .integration_environments.create!
    end
  end
end
