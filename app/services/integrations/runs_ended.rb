module Integrations
  # A deploy or a CI run a connected provider reports has ended, in one shape whichever provider sent it. A provider's
  # event source may answer runs_ended(payload, headers:) with Runs, so a workflow whose trigger is a deploy or CI run
  # ending starts as the provider tells Firefight. Nothing here names a provider.
  module RunsEnded
    KIND_DEPLOY = Workflow::Trigger::Fields::RUN_DEPLOY
    KIND_CI = Workflow::Trigger::Fields::RUN_CI
    KINDS = Workflow::Trigger::Fields::RUN_KINDS
    OUTCOME_SUCCEEDED = Workflow::Trigger::Fields::RUN_SUCCEEDED
    OUTCOME_FAILED = Workflow::Trigger::Fields::RUN_FAILED
    OUTCOME_CANCELLED = Workflow::Trigger::Fields::RUN_CANCELLED
    OUTCOMES = Workflow::Trigger::Fields::RUN_OUTCOMES


    # One run that ended: a deploy or a CI run, how it ended, the provider's own id for it (unique within the provider,
    # one per attempt), its name, the repository, site or project it ran for, its branch or environment, the commit it
    # ran, and the provider's page for it.
    Run = Data.define(:kind, :outcome, :provider, :reference, :name, :place, :ref, :commit, :url, :environment) do
      def initialize(name: nil, ref: nil, commit: nil, url: nil, environment: nil, **) = super
    end

    module_function

    # What a delivery to a connection says ended, through its provider's event source, or none.
    def of(provider_key, payload, headers:)
      source = MapEvents.source_of(provider_key)
      return [] unless source.respond_to?(:runs_ended)

      Array(source.runs_ended(payload, headers: headers)).select { |run| KINDS.include?(run.kind) && OUTCOMES.include?(run.outcome) }
    rescue StandardError => error
      Rails.logger.warn({ event: "runs_ended.unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end
  end
end
