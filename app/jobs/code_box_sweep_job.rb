# Stops boxes nothing has used for an hour, and boxes a provider still runs that no run knows about, such as one left by
# a worker that died between starting it and writing it down.
class CodeBoxSweepJob < ApplicationJob
  queue_as :background

  def perform
    Integrations::CodeReading.sweep!
  end
end
