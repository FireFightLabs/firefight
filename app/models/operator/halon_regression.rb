module Operator
  # Regression runs and their cases, read from what the app records about each run.
  class HalonRegression
    Tally = Data.define(:passed, :failed, :errored, :pending, :skipped) do
      def total = passed + failed + errored + pending + skipped
    end
    # A run with its counts, and a case with how the same case did in the run before on the same model.
    Row = Data.define(:run, :tally)
    Case = Data.define(:result, :previous_status) do
      def newly_failing? = result.status == Investigation::RegressionResult::STATUS_FAILED && previous_status == Investigation::RegressionResult::STATUS_PASSED
    end
    # What needs reading first: what used to pass and now fails, then the rest of the failures.
    CASE_ORDER = [
      Investigation::RegressionResult::STATUS_FAILED, Investigation::RegressionResult::STATUS_ERRORED,
      Investigation::RegressionResult::STATUS_PENDING, Investigation::RegressionResult::STATUS_PASSED,
      Investigation::RegressionResult::STATUS_SKIPPED
    ].freeze
    ModelChoice = Data.define(:id, :name, :provider)

    # Counts for every run on the page in one query.
    def self.rows(runs)
      counts = Investigation::RegressionResult.where(regression_run_id: runs.map(&:id)).group(:regression_run_id, :status).count
      runs.map do |run|
        Row.new(run: run, tally: Tally.new(**Investigation::RegressionResult::STATUSES.to_h { |status| [ status.to_sym, counts[[ run.id, status ]].to_i ] }))
      end
    end

    def self.cases(run)
      before = run.previous&.results&.pluck(:finding_id, :status).to_h
      run.results.includes(:replay, finding: { investigation: %i[workspace subject] }).order(:created_at).map do |result|
        Case.new(result: result, previous_status: before[result.finding_id])
      end.sort_by.with_index { |entry, index| [ entry.newly_failing? ? 0 : 1, CASE_ORDER.index(entry.result.status), index ] }
    end

    def self.cases_available = Investigation::Finding.regression_cases.count
    def self.workspaces_opted_in = Workspace.where(halon_regression_enabled: true).count

    def self.models
      FirefightAi.priced_chat_models.map { |model| ModelChoice.new(id: model.id, name: model.name, provider: model.provider.to_s) }
                 .sort_by { |model| [ model.provider, model.name ] }
    end

    def self.model(id) = models.find { |model| model.id == id }
  end
end
