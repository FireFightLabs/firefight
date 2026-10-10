module FirefightAi
  module Schemas
    class ReplayVerdict < ::Schematist::Schema
      REACHED = "reached".freeze
      PARTLY = "partly".freeze
      MISSED = "missed".freeze
      OUTCOMES = [ REACHED, PARTLY, MISSED ].freeze

      YES = "yes".freeze
      NO = "no".freeze
      FORWARD = [ YES, PARTLY, NO ].freeze

      description "How an agent did in a replayed chat: whether it reached the right outcome, moved the work forward without being pushed, " \
                  "and which of its questions to the person it could have answered itself"

      string :outcome, enum: OUTCOMES, description: "reached when its answers get to the outcome described, partly when they get some of it or hedge " \
                                                    "it, missed when they do not get there or get it wrong"
      string :moved_forward, enum: FORWARD, description: "yes when it proposed the next step and took it once allowed, without the person having " \
                                                         "to ask, partly when it only proposed it or took only some of it, no when it stopped and waited to be told"
      integer :questions, description: "How many questions its replies put to the person, a confirmation card not counted"
      integer :unneeded_questions, description: "How many of those it could have answered itself from what its tools returned or could " \
                                                "have read, including asking permission to read something"
      string :reason, description: "Why, in two or three plain sentences naming what it got right and what it missed"
    end
  end
end
