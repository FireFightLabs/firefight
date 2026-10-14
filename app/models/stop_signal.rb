# A stop a person pressed, reaching work that waits a long time on their behalf, such as a command in a sandbox. Whoever
# runs that work (FirefightAi::AgentLoop around a tool) hands it a signal in fiber storage, which the fibers and threads
# the work starts inherit. Code that waits checks it as it waits, so it gives up and tidies after itself at once.
module StopSignal
  KEY = :firefight_stop_signal
  # How often a wait looks for a stop.
  CHECK_EVERY = 0.2

  # Raised where the work gives up. A StandardError, so the ledger records the call as ended rather than leaving it open.
  class Stopped < StandardError
    def initialize(message = "Stopped before it finished.") = super
  end

  # signal is anything that answers set?, such as a Concurrent::Event its owner sets.
  def self.watching(signal)
    previous = Fiber[KEY]
    Fiber[KEY] = signal
    yield
  ensure
    Fiber[KEY] = previous
  end

  def self.stopped? = Fiber[KEY]&.set? == true

  def self.check! = (raise Stopped if stopped?)

  # As sleep, given up at once when the work is stopped.
  def self.pause(seconds)
    deadline = clock + seconds
    loop do
      check!
      left = deadline - clock
      break unless left.positive?

      sleep [ left, CHECK_EVERY ].min
    end
  end

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
