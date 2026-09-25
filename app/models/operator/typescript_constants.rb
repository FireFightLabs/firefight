module Operator
  # Operator values the pages need, by constant name. lib/typescript_constants.rb adds them to the generated frontend
  # constants.
  module TypescriptConstants
    def self.exports
      {
        "OPERATOR_WORKFLOW_STATES" => WorkflowRuns::STATES.index_by(&:upcase),
        "OPERATOR_STEP_STATUSES" => WorkflowRuns::STEP_STATUSES.index_by(&:upcase),
        "OPERATOR_PROCESS_KINDS" => IncidentProcess::KINDS.index_by(&:upcase),
        "OPERATOR_PROCESS_TONES" => IncidentProcess::TONES.index_by(&:upcase),
        "OPERATOR_HALON_ENDINGS" => HalonRuns::ENDINGS.index_by(&:upcase),
        "OPERATOR_TRACE_KINDS" => Trace::KINDS.index_by(&:upcase),
        "OPERATOR_FIND_KINDS" => Finder::KINDS.index_by(&:upcase),
        "OPERATOR_WINDOWS" => { "DAY" => Filter::WINDOW_DAY, "WEEK" => Filter::WINDOW_WEEK, "MONTH" => Filter::WINDOW_MONTH },
        "OPERATOR_SPAN_PARAM" => Trace::SPAN_PARAM,
        "OPERATOR_SPAN_BODY_PROP" => Trace::BODY_PROP
      }
    end
  end
end
