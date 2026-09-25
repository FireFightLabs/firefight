module Operator
  # When the console may act on a record. Each method returns a sentence saying why not, or nil when the action is
  # allowed. Controllers refuse with the sentence, and pages show the button only when it is nil.
  module Actions
    def self.step_blocked_reason(step)
      "Only a failed step can be run again or skipped." unless step.failed?
    end

    def self.pause_blocked_reason(workflow)
      "Only a waiting or running workflow can be paused." unless workflow.pending? || workflow.running?
    end

    def self.resume_blocked_reason(workflow)
      "Only a paused workflow can be resumed." unless workflow.paused?
    end

    def self.cancel_blocked_reason(workflow)
      "This workflow has already finished." unless workflow.pending? || workflow.running? || workflow.paused?
    end

    def self.redelivery_blocked_reason(delivery)
      "Only a failed delivery can be sent again." unless delivery.failed?
    end
  end
end
