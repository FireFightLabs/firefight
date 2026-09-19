# Spend was kept in whole cents, and each turn rounded up to the next one, so every question in a
# conversation or run overstated its cost by up to a cent. Micros are what the Inference ledger uses.
# Rows already written keep the cents they had, since the exact figure behind them is gone.
class CountAgentSpendInMicros < ActiveRecord::Migration[8.1]
  TABLES = %i[conversations investigations].freeze
  MICROS_PER_CENT = 10_000

  def up
    TABLES.each do |table|
      add_column table, :spent_micros, :bigint, default: 0, null: false
      execute "UPDATE #{table} SET spent_micros = spent_cents::bigint * #{MICROS_PER_CENT}"
      remove_column table, :spent_cents
    end
  end

  def down
    TABLES.each do |table|
      add_column table, :spent_cents, :integer, default: 0, null: false
      execute "UPDATE #{table} SET spent_cents = CEIL(spent_micros / #{MICROS_PER_CENT}.0)::integer"
      remove_column table, :spent_micros
    end
  end
end
