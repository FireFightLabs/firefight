# One condition of the rule engine: a field, an operator and a value, matched against a flat context of strings. A
# policy's rules and a workflow's trigger are both lists of these, so what a condition means is decided here once.
module Policy::Conditions
  REGEX_TIMEOUT_SECONDS = 0.1

  module_function

  # How one condition went against the context, with the value it saw, as the route tester shows it.
  def evaluate(condition, context)
    condition = condition.with_indifferent_access
    field = condition[:field].to_s
    operator = condition[:operator]
    value = condition[:value]
    actual = context[field]

    { field: field, operator: operator, value: value, actual: actual, matched: matched?(operator, value, actual) }
  end

  # Whether every condition holds. No conditions hold for everything.
  def all?(conditions, context)
    normalized = Policy.normalize_context(context)
    Array(conditions).all? { |condition| evaluate(condition, normalized)[:matched] }
  end

  def matched?(operator, value, actual)
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
  end

  # The timeout guards against ReDoS from user-authored patterns.
  def regex_match?(pattern, actual)
    Regexp.new(pattern, timeout: REGEX_TIMEOUT_SECONDS).match?(actual)
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  # Each problem with a list of conditions, as a sentence. Patterns are compiled here so one that cannot be read is
  # refused when it is saved rather than never matching.
  def errors_for(conditions)
    return [ "must be a list of conditions" ] unless conditions.is_a?(Array)

    conditions.each_with_index.flat_map do |condition, index|
      next [ "Condition #{index + 1} is not readable" ] unless condition.is_a?(Hash)

      condition = condition.with_indifferent_access
      found = []
      found << "Condition #{index + 1} needs a field" if condition[:field].blank?
      operator = condition[:operator]
      next found + [ "Condition #{index + 1} has an unknown operator" ] unless PolicyRule::OPERATORS.include?(operator)

      found + value_errors(condition[:value], operator, index)
    end
  end

  def value_errors(value, operator, index)
    found = []
    if PolicyRule::ARRAY_VALUE_OPERATORS.include?(operator) && !(value.is_a?(Array) && value.any?)
      found << "Condition #{index + 1} needs at least one value"
    end
    if PolicyRule::STRING_VALUE_OPERATORS.include?(operator) && !(value.is_a?(String) && value.present?)
      found << "Condition #{index + 1} needs a value"
    end
    if operator == PolicyRule::OPERATOR_MATCHES_REGEX && value.is_a?(String)
      begin
        Regexp.new(value)
      rescue RegexpError => e
        found << "Condition #{index + 1} has a pattern Firefight cannot read: #{e.message}"
      end
    end
    found
  end
end
