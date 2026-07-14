# First-match-wins rule evaluation. Pure (no side effects) and returns a full
# trace, so the same call powers routing, the route-tester UI, and future
# read-only MCP tools. Domain consumers interpret the outcome; evaluation
# never does.
module Policy::Evaluation
  extend ActiveSupport::Concern

  REGEX_TIMEOUT_SECONDS = 0.1

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

  def evaluate_condition(condition, context)
    condition = condition.with_indifferent_access
    field = condition[:field].to_s
    operator = condition[:operator]
    value = condition[:value]
    actual = context[field]

    matched =
      case operator
      when PolicyRule::OPERATOR_IS_ONE_OF
        Array(value).map(&:to_s).include?(actual)
      when PolicyRule::OPERATOR_CONTAINS
        actual.present? && actual.include?(value.to_s)
      when PolicyRule::OPERATOR_STARTS_WITH
        actual.present? && actual.start_with?(value.to_s)
      when PolicyRule::OPERATOR_MATCHES_REGEX
        actual.present? && regex_match?(value.to_s, actual)
      when PolicyRule::OPERATOR_IS_EMPTY
        actual.blank?
      else
        false
      end

    { field: field, operator: operator, value: value, actual: actual, matched: matched }
  end

  # Timeout guards against ReDoS from user-authored patterns; invalid patterns
  # are also rejected at write time by PolicyRule validation.
  def regex_match?(pattern, actual)
    Regexp.new(pattern, timeout: REGEX_TIMEOUT_SECONDS).match?(actual)
  rescue RegexpError, Regexp::TimeoutError
    false
  end
end
