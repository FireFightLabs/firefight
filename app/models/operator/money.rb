module Operator
  # Spend is kept in micros, millionths of a dollar, and read by operators in dollars.
  module Money
    MICROS_PER_DOLLAR = 1_000_000

    def self.dollars(micros)
      ActiveSupport::NumberHelper.number_to_currency(micros.to_i / MICROS_PER_DOLLAR.to_f)
    end
  end
end
