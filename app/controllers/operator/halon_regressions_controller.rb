module Operator
  # Regression runs: the latest rated answers replayed on a version of Halon, and which ones it now gets wrong.
  class HalonRegressionsController < BaseController
    PER_PAGE = 25

    def index
      page = [ params[:page].to_i, 1 ].max
      runs = Investigation::RegressionRun.recent.includes(:started_by).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/halon/regression", props: {
        runs: HalonRegressionRunSerializer.many(HalonRegression.rows(runs.first(PER_PAGE))),
        casesAvailable: HalonRegression.cases_available,
        caseLimit: Investigation::RegressionRun::CASES,
        workspacesOptedIn: HalonRegression.workspaces_opted_in,
        promptVersion: Investigation::Regression.prompt_version,
        runBlockedReason: Actions.regression_blocked_reason,
        HalonRegression::MODELS_PROP => InertiaRails.optional { HalonRegressionModelSerializer.many(HalonRegression.models) },
        page: page, more: runs.size > PER_PAGE
      }
    end

    def show
      run = Investigation::RegressionRun.includes(:started_by).find(params[:id])

      render inertia: "operator/halon/regression-run", props: {
        run: HalonRegressionRunSerializer.one(HalonRegression.rows([ run ]).sole),
        cases: HalonRegressionCaseSerializer.many(HalonRegression.cases(run))
      }
    end

    def create
      blocked = Actions.regression_blocked_reason
      return redirect_to(operator_halon_regressions_path, alert: blocked) if blocked

      chosen = params[:model].presence && HalonRegression.model(params[:model], params[:provider])
      return redirect_to(operator_halon_regressions_path, alert: "That model is not one Firefight can price, so choose another.") if params[:model].present? && !chosen

      run = Investigation::Regression.start!(trigger: Investigation::RegressionRun::TRIGGER_OPERATOR, model: chosen&.id, provider: chosen&.provider, by: current_user)
      return redirect_to(operator_halon_regressions_path, alert: Actions.regression_blocked_reason || "No workspace has a rated answer to test on yet.") unless run

      redirect_to operator_halon_regression_path(run), notice: "Replaying #{helpers.pluralize(run.results.size, 'rated answer')} on #{chosen&.name || "Halon's model"}."
    end
  end
end
