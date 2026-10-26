module Integrations
  # The check a pull request review sets on the pull request's head commit, passing or failing, in one shape whichever
  # code host holds it. A code host's pack answers set_review_check(environment_row, repository:, sha:, check:) by
  # posting a commit status under NAME, which the host shows beside the pull request's other checks and a branch rule
  # can require. Nothing here names a host.
  module ReviewChecks
    PASSING = "passing".freeze
    FAILING = "failing".freeze
    STATES = [ PASSING, FAILING ].freeze

    # What the check is called on every host, and the key a host that asks for one files it under.
    NAME = "Halon review".freeze
    KEY = "firefight-halon-review".freeze
    # The shortest any host keeps of a check's words.
    DESCRIPTION_LIMIT = 140

    # description says why it stands where it does. url opens where a person can see the findings and override them.
    Check = Data.define(:state, :description, :url) do
      def passing? = state == PASSING

      def short_description = description.to_s.truncate(DESCRIPTION_LIMIT)
    end

    module_function

    def sets?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && pack.method_defined?(:set_review_check)
    end

    def set!(environment_row, repository:, sha:, check:)
      raise ArgumentError, "#{check.state} is not a check state" unless STATES.include?(check.state)

      NativePack.fetch!(environment_row.integration).set_review_check(environment_row, repository: repository, sha: sha, check: check)
    end
  end
end
