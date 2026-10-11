module FirefightAi
  module Schemas
    class Challenge < ::Schematist::Schema
      HOLDS = "holds".freeze
      CONTRADICTED = "contradicted".freeze
      STRONGER_ALTERNATIVE = "stronger_alternative".freeze
      VERDICTS = [ HOLDS, CONTRADICTED, STRONGER_ALTERNATIVE ].freeze

      description "Whether anything read so far speaks against the cause named"

      string :verdict, enum: VERDICTS,
                       description: "holds when nothing read speaks against it, contradicted when a read does, stronger_alternative when the reads point at another cause nobody checked"
      string :reason, description: "The read that speaks against it, or the alternative and why, in one or two plain sentences. Empty when it holds"
      array :checks, of: :string, description: "At most two reads that would settle it, each one sentence naming what to read. Empty when it holds"
    end
  end
end
