module Integrations
  # Once a day, what normal looks like for every resource on the map that its provider reads metrics for. Without a row
  # it queues one read per connection, and with one it reads that connection.
  class BaselineSweepJob < ApplicationJob
    queue_as :background

    def perform(environment_row = nil)
      return BaselineSweep.run!(environment_row) if environment_row

      BaselineSweep.queue_all
    end
  end
end
