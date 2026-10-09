module Operator
  # Operator values the pages need, by constant name, written to the console's own generated file so the app's
  # constants never name the console. bin/rails typescript:constants writes both.
  module TypescriptConstants
    OUTPUT = Rails.root.join("app/frontend/pages/operator/generated/constants.ts")

    def self.exports
      {
        "OPERATOR_WORKFLOW_STATES" => WorkflowRuns::STATES.index_by(&:upcase),
        "OPERATOR_STEP_STATUSES" => WorkflowRuns::STEP_STATUSES.index_by(&:upcase),
        "OPERATOR_PROCESS_KINDS" => IncidentProcess::KINDS.index_by(&:upcase),
        "OPERATOR_PROCESS_TONES" => IncidentProcess::TONES.index_by(&:upcase),
        "OPERATOR_HALON_ENDINGS" => HalonRuns::ENDINGS.index_by(&:upcase),
        "OPERATOR_REGRESSION_CASE_STATUSES" => Investigation::RegressionResult::STATUSES.index_by(&:upcase),
        "OPERATOR_REGRESSION_EXPECTED" => Investigation::RegressionResult::EXPECTED.index_by(&:upcase),
        "OPERATOR_REGRESSION_TRIGGERS" => Investigation::RegressionRun::TRIGGERS.index_by(&:upcase),
        "OPERATOR_REGRESSION_RUN_STATUSES" => Investigation::RegressionRun::STATUSES.index_by(&:upcase),
        "OPERATOR_TRACE_KINDS" => Trace::KINDS.index_by(&:upcase),
        "OPERATOR_FIND_KINDS" => Finder::KINDS.index_by(&:upcase),
        "OPERATOR_WINDOWS" => { "DAY" => Filter::WINDOW_DAY, "WEEK" => Filter::WINDOW_WEEK, "MONTH" => Filter::WINDOW_MONTH },
        "OPERATOR_SPAN_PARAM" => Trace::SPAN_PARAM,
        "OPERATOR_SPAN_BODY_PROP" => Trace::BODY_PROP,
        "OPERATOR_REGRESSION_MODELS_PROP" => HalonRegression::MODELS_PROP
      }
    end

    def self.render
      exports.each_with_object(::TypescriptConstants::HEADER.dup) do |(name, value), out|
        out << "\nexport const #{name} = #{JSON.pretty_generate(value)} as const\n"
      end
    end

    def self.write!
      OUTPUT.dirname.mkpath
      OUTPUT.write(render)
    end

    def self.current?
      OUTPUT.exist? && OUTPUT.read == render
    end
  end
end
