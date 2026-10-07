require "test_helper"

class EntitlementsSweepJobTest < ActiveJob::TestCase
  SweepingBackend = Struct.new(:swept) do
    def check(_workspace, _feature) = Entitlements.allow
    def sweep! = self.swept = true
  end

  test "a backend with daily upkeep runs it" do
    backend = SweepingBackend.new(false)
    Entitlements.backend = backend

    EntitlementsSweepJob.perform_now

    assert backend.swept
  end

  test "an install someone runs themselves has nothing to sweep" do
    assert_nothing_raised { EntitlementsSweepJob.perform_now }
    assert_nil Entitlements.sweep!
  end
end
