require "test_helper"
require "async"
require "async/barrier"

class BlockingTest < ActiveSupport::TestCase
  BUSY = 0.3

  test "outside a fiber worker the work runs in place" do
    assert_equal Thread.current, Blocking.call { Thread.current }
  end

  test "inside a fiber worker the work runs on a thread of its own and the other jobs carry on meanwhile" do
    order = []
    Async do
      barrier = Async::Barrier.new
      barrier.async { Blocking.call { busy(BUSY) }.then { order << :blocking } }
      barrier.async { order << :other }
      barrier.wait
    end.wait

    assert_equal [ :other, :blocking ], order
  end

  test "inside a fiber worker a Timeout around work that never waits still cuts it short" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raised = Async do
      Blocking.call { Timeout.timeout(0.05) { busy(BUSY) } }
    rescue Timeout::Error => error
      error
    end.wait

    assert_kind_of Timeout::Error, raised
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, BUSY
  end

  test "an error inside the work reaches the caller" do
    raised = Async do
      Blocking.call { raise ArgumentError, "refused" }
    rescue ArgumentError => error
      error
    end.wait

    assert_equal "refused", raised.message
  end

  private

  def busy(seconds)
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    nil while Process.clock_gettime(Process::CLOCK_MONOTONIC) < finish
  end
end
