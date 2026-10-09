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

    def self.regression_blocked_reason
      return "No workspace has a rated answer to test on yet." unless Investigation::Finding.regression_cases.exists?

      "A regression run is still going. Start another once it finishes." if Investigation::RegressionRun.exists?(status: Investigation::RegressionRun::STATUS_RUNNING)
    end

    def self.redelivery_blocked_reason(delivery)
      "Only a failed delivery can be sent again." unless delivery.failed?
    end

    # Blank holds the workspace to no provider, so it follows the deployment's own.
    def self.sandbox_placement_blocked_reason(key)
      return if key.blank? || SandboxProviders::KEYS.include?(key)

      "#{key} is not a sandbox provider. Choose one of #{SandboxProviders::KEYS.map { |each| SandboxProviders.name_of(each) }.to_sentence(last_word_connector: ' or ')}."
    end
  end
end
