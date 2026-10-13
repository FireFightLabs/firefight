module SolidWorkflow
  # A branch's test, read once its references are filled: a comparison of left and right, or all, any or not of other
  # conditions. Numbers written as text compare as numbers.
  module Condition
    OPERATOR_EQUALS = "equals".freeze
    OPERATOR_NOT_EQUALS = "not_equals".freeze
    OPERATOR_IS_ONE_OF = "is_one_of".freeze
    OPERATOR_CONTAINS = "contains".freeze
    OPERATOR_STARTS_WITH = "starts_with".freeze
    OPERATOR_MATCHES_REGEX = "matches_regex".freeze
    OPERATOR_IS_EMPTY = "is_empty".freeze
    OPERATOR_IS_NOT_EMPTY = "is_not_empty".freeze
    OPERATOR_GREATER_THAN = "greater_than".freeze
    OPERATOR_GREATER_OR_EQUAL = "greater_or_equal".freeze
    OPERATOR_LESS_THAN = "less_than".freeze
    OPERATOR_LESS_OR_EQUAL = "less_or_equal".freeze
    OPERATORS = [
      OPERATOR_EQUALS, OPERATOR_NOT_EQUALS, OPERATOR_IS_ONE_OF, OPERATOR_CONTAINS, OPERATOR_STARTS_WITH,
      OPERATOR_MATCHES_REGEX, OPERATOR_IS_EMPTY, OPERATOR_IS_NOT_EMPTY, OPERATOR_GREATER_THAN, OPERATOR_GREATER_OR_EQUAL,
      OPERATOR_LESS_THAN, OPERATOR_LESS_OR_EQUAL
    ].freeze
    VALUELESS = [ OPERATOR_IS_EMPTY, OPERATOR_IS_NOT_EMPTY ].freeze
    ALL = "all".freeze
    ANY = "any".freeze
    NOT = "not".freeze
    # A pattern from step data cannot hold a worker for long.
    REGEX_TIMEOUT = 1.0

    module_function

    def well_formed?(condition)
      return false unless condition.is_a?(Hash)

      condition = condition.stringify_keys
      return condition[ALL].is_a?(Array) && condition[ALL].any? && condition[ALL].all? { |inner| well_formed?(inner) } if condition.key?(ALL)
      return condition[ANY].is_a?(Array) && condition[ANY].any? && condition[ANY].all? { |inner| well_formed?(inner) } if condition.key?(ANY)
      return well_formed?(condition[NOT]) if condition.key?(NOT)

      OPERATORS.include?(condition["operator"]) && condition.key?("left") && (VALUELESS.include?(condition["operator"]) || condition.key?("right"))
    end

    def met?(condition)
      condition = condition.to_h.stringify_keys
      return condition[ALL].all? { |inner| met?(inner) } if condition.key?(ALL)
      return condition[ANY].any? { |inner| met?(inner) } if condition.key?(ANY)
      return !met?(condition[NOT]) if condition.key?(NOT)

      compare(condition["left"], condition["operator"], condition["right"])
    end

    def compare(left, operator, right)
      case operator
      when OPERATOR_EQUALS then same?(left, right)
      when OPERATOR_NOT_EQUALS then !same?(left, right)
      when OPERATOR_IS_ONE_OF then Array(right).any? { |candidate| same?(left, candidate) }
      when OPERATOR_CONTAINS then left.is_a?(Array) ? left.any? { |item| same?(item, right) } : left.to_s.include?(right.to_s)
      when OPERATOR_STARTS_WITH then left.to_s.start_with?(right.to_s)
      when OPERATOR_MATCHES_REGEX then Regexp.new(right.to_s, timeout: REGEX_TIMEOUT).match?(left.to_s)
      when OPERATOR_IS_EMPTY then left.blank?
      when OPERATOR_IS_NOT_EMPTY then left.present?
      when OPERATOR_GREATER_THAN then ordered(left, right) { |a, b| a > b }
      when OPERATOR_GREATER_OR_EQUAL then ordered(left, right) { |a, b| a >= b }
      when OPERATOR_LESS_THAN then ordered(left, right) { |a, b| a < b }
      when OPERATOR_LESS_OR_EQUAL then ordered(left, right) { |a, b| a <= b }
      else raise ArgumentError, "Unknown condition operator #{operator.inspect}"
      end
    rescue RegexpError, Regexp::TimeoutError
      false
    end

    def same?(left, right)
      numbers = [ number(left), number(right) ]
      return numbers.first == numbers.last if numbers.none?(&:nil?)

      left.to_s == right.to_s
    end

    def ordered(left, right)
      a = number(left)
      b = number(right)
      return yield(a, b) if a && b

      yield(left.to_s, right.to_s)
    end

    def number(value)
      return value if value.is_a?(Numeric)
      return unless value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/)

      Float(value)
    end
  end
end
