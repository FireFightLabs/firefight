module FirefightAi
  module Schemas
    class WatchReading < ::Schematist::Schema
      NOT_STARTED = "not_started".freeze
      RUNNING = "running".freeze
      DONE = "done".freeze
      FAILED = "failed".freeze
      STATES = [ NOT_STARTED, RUNNING, DONE, FAILED ].freeze

      PART_WAITING = "waiting".freeze
      PART_RUNNING = "running".freeze
      PART_PASSED = "passed".freeze
      PART_FAILED = "failed".freeze
      PART_STATES = [ PART_WAITING, PART_RUNNING, PART_PASSED, PART_FAILED ].freeze

      description "Where a reading of a production system shows the thing being watched: not started, running, done or failed, and each job or step it lists"

      string :state, enum: STATES, description: "not_started when the reading shows it has not begun, running once it shows it has begun and is not over, " \
                                                "done when it shows the goal reached, failed when it shows it went wrong"
      string :said, description: "One short plain sentence saying what the reading shows, such as \"web is running the new version on 2 of 2 instances\""
      array :parts, description: "Each job or step inside it the reading lists, in its order. Empty when it lists none" do
        object do
          string :name, description: "The job's or step's name exactly as the reading gives it"
          string :state, enum: PART_STATES, description: "waiting, running, passed or failed, as the reading shows it"
        end
      end
    end
  end
end
