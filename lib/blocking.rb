# Work that never hands its thread back while it waits, kept from stalling a fiber worker (config/queue.yml). A C
# extension's own network call or a long stretch of pure computation holds the one thread every job of that worker
# shares, and a Timeout around it cannot fire until it ends. Under a fiber scheduler the work runs on a thread of its
# own, which the calling fiber waits on while the others carry on. Anywhere else it runs in place.
module Blocking
  def self.call(&work)
    return work.call unless Fiber.scheduler

    thread = Thread.new do
      run = Rails.application.executor.run!
      begin
        work.call
      ensure
        run.complete!
      end
    end
    thread.report_on_exception = false
    thread.value
  end
end
