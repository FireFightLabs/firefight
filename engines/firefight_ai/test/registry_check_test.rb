require "test_helper"

class FirefightAi::RegistryCheckTest < ActiveSupport::TestCase
  test "a request in a test never asks whether the models table changed, so what a page costs does not depend on how long its worker ran" do
    later = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.day.to_i
    FirefightAi.expects(:reload_registry_if_changed!).never
    Process.stubs(:clock_gettime).returns(later)

    Rails.application.executor.wrap { nil }
  end

  test "a process asks whether the models table changed at most once a minute" do
    FirefightAi.unstub(:keep_registry_current)
    later = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.year.to_i
    FirefightAi.expects(:reload_registry_if_changed!).twice

    [ later, later + FirefightAi::REGISTRY_CHECK_SECONDS - 1, later + FirefightAi::REGISTRY_CHECK_SECONDS ].each do |now|
      Process.stubs(:clock_gettime).returns(now)
      FirefightAi.keep_registry_current
    end
  end
end
