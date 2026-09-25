module Operator
  # Spend is stored in micros, millionths of a dollar. This formats it in dollars.
  module Money
    MICROS_PER_DOLLAR = 1_000_000

    def self.dollars(micros)
      ActiveSupport::NumberHelper.number_to_currency(micros.to_i / MICROS_PER_DOLLAR.to_f)
    end
  end
end
