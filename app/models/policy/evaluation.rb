# First match wins. No side effects and a full trace, so the same call powers
# routing and the route tester. Domain consumers interpret the outcome.
module Policy::Evaluation
  extend ActiveSupport::Concern

  REGEX_TIMEOUT_SECONDS = Policy::Conditions::REGEX_TIMEOUT_SECONDS

  Result = Struct.new(:matched_rule, :outcome, :trace, keyword_init: true) do
    def matched?
      matched_rule.present?
    end
  end

  class_methods do
    def normalize_context(context)
      context.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s] = value.nil? ? nil : value.to_s
      end
    end
  end

  def evaluate(context)
    return Result.new(matched_rule: nil, outcome: nil, trace: []) unless enabled?

    normalized = self.class.normalize_context(context)
    trace = []

    ordered_rules.each do |rule|
      unless rule.enabled?
        trace << { rule_id: rule.id, priority: rule.priority, matched: false, skipped: true, conditions: [] }
        next
      end

      condition_results = rule.conditions.map { |condition| evaluate_condition(condition, normalized) }
      matched = condition_results.all? { |result| result[:matched] }

      trace << {
        rule_id: rule.id,
        priority: rule.priority,
        matched: matched,
        skipped: false,
        conditions: condition_results
      }

      return Result.new(matched_rule: rule, outcome: rule.outcome, trace: trace) if matched
    end

    Result.new(matched_rule: nil, outcome: nil, trace: trace)
  end

  private

  def evaluate_condition(condition, context) = Policy::Conditions.evaluate(condition, context)
end
