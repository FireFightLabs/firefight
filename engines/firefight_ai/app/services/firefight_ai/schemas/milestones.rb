module FirefightAi
  module Schemas
    class Milestones < ::RubyLLM::Schema
      # The one array this schema returns. The extractor reads the response by
      # this key, so it lives here rather than as a string on both sides.
      ROOT_KEY = "milestones".freeze

      description "The genuine milestones of an incident's investigation, read from its channel transcript"

      array :milestones do
        object do
          string :kind,
                 enum: ::IncidentEvent::MILESTONE_KINDS,
                 description: "What this milestone is: a theory, a confirmed finding, the root cause, " \
                              "a mitigation applied, a decision taken, a blocker, a statement of impact, " \
                              "or a return to normal"
          string :statement,
                 description: "One sentence in the past tense naming who it belongs to, e.g. " \
                              "'Diego suspects the 14:02 deploy'. No trailing period."
          string :message_id,
                 description: "The message_id of the single transcript message this milestone came from, copied exactly"
          number :confidence,
                 description: "How sure you are this is a genuine milestone and not chatter, between 0 and 1"
        end
      end
    end
  end
end
