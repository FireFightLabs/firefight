module FirefightAi
  module Schemas
    class WatchReading < ::Schematist::Schema
      DONE = "done".freeze
      FAILED = "failed".freeze
      GOING = "going".freeze

      description "Whether a reading of a production system shows the thing being watched is done, failed or still going"

      string :state, enum: [ DONE, FAILED, GOING ], description: "done when the reading shows the goal reached, failed when it shows it went wrong, going otherwise"
      string :said, description: "One short plain sentence saying what the reading shows, such as \"web is running the new version on 2 of 2 instances\""
    end
  end
end
